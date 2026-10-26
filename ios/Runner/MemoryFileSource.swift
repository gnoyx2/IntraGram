import Flutter
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// intragram/file_source 채널: 모바일 문서·사진 선택을 캐시 사본 없이 RAM으로 흘려 넘김.
// UIDocumentPickerViewController를 asCopy: false로 열어서 앱 캐시로 안 복사하고, security-scoped URL은
// RAM(딕셔너리)에만 들고 있다가 release에서 scope를 놓음. 사진은 PHPickerViewController(별도 프로세스라
// 사진 보관함 권한 팝업이 없음)로 고른 것만 받아 바이트를 RAM에만 두고 release에서 버림
// 계약: pick(imagesOnly) -> [{id,name,size}], open(sourceId) -> readerId, read(readerId, maxBytes) -> bytes|nil(EOF),
// close(readerId), release(sourceId), releaseAll(). read는 Dart가 다음 조각을 달라고 할 때만 불려서 버퍼가 끝없이 안 쌓임
final class MemoryFileSource: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
  private static let photoLimit = 10
  private static let photoBudget = 50 * 1024 * 1024

  private struct Source {
    let url: URL
    let name: String
    let size: Int
  }

  private var photos: [String: Data] = [:]
  private var photoReaders: [String: (sourceId: String, offset: Int)] = [:]
  private weak var activePicker: UIViewController?
  private var photoProgress: Progress?

  private var sources: [String: Source] = [:]
  private var readers: [String: FileHandle] = [:]
  private var pendingPick: FlutterResult?

  // releaseAll()마다 오름. 그 순간 도는 pick·open은 시작할 때 잡은 값과 나중에 비교해서
  // 다르면 방금 얻은 소스·핸들을 등록 안 하고 바로 버림
  private var generation = 0
  private var pendingPickGeneration = 0
  private let ioQueue = DispatchQueue(
    label: "intragram.file_source.io",
    qos: .userInitiated
  )

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let channel = FlutterMethodChannel(
      name: "intragram/file_source",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "pick":
      pick(imagesOnly: args?["imagesOnly"] as? Bool ?? false, result: result)
    case "open":
      guard let sourceId = args?["sourceId"] as? String else {
        result(FlutterError(code: "bad_args", message: "sourceId required", details: nil))
        return
      }
      open(sourceId: sourceId, result: result)
    case "read":
      guard let readerId = args?["readerId"] as? String,
        let maxBytes = args?["maxBytes"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "readerId/maxBytes required", details: nil))
        return
      }
      read(readerId: readerId, maxBytes: maxBytes, result: result)
    case "close":
      close(readerId: args?["readerId"] as? String)
      result(nil)
    case "release":
      release(sourceId: args?["sourceId"] as? String)
      result(nil)
    case "releaseAll":
      releaseAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // 지금 키 윈도우의 맨 위 뷰컨트롤러 (모달이 떠 있으면 그 위에 띄움). 미리 들고 있지 않고 부를 때마다 찾음
  private func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func pick(imagesOnly: Bool, result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      result(FlutterError(code: "busy", message: "another pick is already in progress", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_presenter", message: "no view controller to present from", details: nil))
      return
    }
    pendingPick = result
    pendingPickGeneration = generation
    if imagesOnly {
      var configuration = PHPickerConfiguration()
      configuration.filter = .images
      configuration.selectionLimit = MemoryFileSource.photoLimit
      // HEIC 등은 JPEG로 받아 Windows/Linux/웹 피어도 미리보기를 그릴 수 있게 함
      configuration.preferredAssetRepresentationMode = .compatible
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      activePicker = picker
      presenter.present(picker, animated: true)
      return
    }
    let types: [UTType] = [.item]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    activePicker = picker
    picker.allowsMultipleSelection = true
    picker.delegate = self
    DispatchQueue.main.async {
      presenter.present(picker, animated: true)
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard picker === activePicker else { return }
    picker.dismiss(animated: true)
    activePicker = nil
    let pickGeneration = pendingPickGeneration
    loadPhotos(results, index: 0, metadata: [], pickGeneration: pickGeneration)
  }

  // 사진 바이트를 RAM(Data)으로만 받음 (파일 표현으로 받으면 앱 tmp에 사본이 생김)
  // 크기는 받은 뒤 남은 예산과 비교함. 하나씩 차례로 읽어 동시 메모리를 줄임
  // 한 번에 photoLimit장·총 photoBudget 상한. 더 크면 파일 선택으로 보내야 함
  private func loadPhotos(
    _ results: [PHPickerResult], index: Int,
    metadata: [[String: Any]], pickGeneration: Int
  ) {
    guard pickGeneration == generation else { return }
    guard index < results.count else {
      let result = pendingPick
      pendingPick = nil
      photoProgress = nil
      result?(metadata)
      return
    }
    let provider = results[index].itemProvider
    guard let type = provider.registeredTypeIdentifiers.first(where: {
      UTType($0)?.conforms(to: .image) == true
    }) else {
      loadPhotos(results, index: index + 1, metadata: metadata, pickGeneration: pickGeneration)
      return
    }
    let remaining = MemoryFileSource.photoBudget - photos.values.reduce(0) { $0 + $1.count }
    photoProgress = provider.loadDataRepresentation(forTypeIdentifier: type) { [weak self] data, _ in
      DispatchQueue.main.async {
        guard let self, pickGeneration == self.generation else { return }
        guard let bytes = data, !bytes.isEmpty, bytes.count <= remaining else {
          for item in metadata {
            if let id = item["id"] as? String { self.photos.removeValue(forKey: id) }
          }
          let result = self.pendingPick
          self.pendingPick = nil
          self.photoProgress = nil
          result?(FlutterError(code: "photo_unavailable", message: "photo unavailable or selection too large", details: nil))
          return
        }
        let id = UUID().uuidString
        let ext = UTType(type)?.preferredFilenameExtension ?? "img"
        let base = provider.suggestedName ?? "Photo"
        let name = (base as NSString).pathExtension.isEmpty ? "\(base).\(ext)" : base
        self.photos[id] = bytes
        self.loadPhotos(results, index: index + 1,
          metadata: metadata + [["id": id, "name": name, "size": bytes.count]],
          pickGeneration: pickGeneration)
      }
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard controller === activePicker else { return }
    activePicker = nil
    let result = pendingPick
    pendingPick = nil
    guard pendingPickGeneration == generation else {
      // 이 pick 도중에 releaseAll이 돎: scope를 아예 안 얻고 빈 결과로 끝냄
      result?([])
      return
    }
    var metadata: [[String: Any]] = []
    for url in urls {
      guard url.startAccessingSecurityScopedResource() else { continue }
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
      guard let size = values?.fileSize else {
        // 크기를 못 구하면(클라우드 전용, 기기에 안 받은 파일 등) scope를 바로 놓고 건너뜀: 네트워크 다운로드를 안 일으킴
        url.stopAccessingSecurityScopedResource()
        continue
      }
      let name = values?.name ?? url.lastPathComponent
      let id = UUID().uuidString
      sources[id] = Source(url: url, name: name, size: size)
      metadata.append(["id": id, "name": name, "size": size])
    }
    result?(metadata)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === activePicker else { return }
    activePicker = nil
    let result = pendingPick
    pendingPick = nil
    result?([])
  }

  private func open(sourceId: String, result: @escaping FlutterResult) {
    if photos[sourceId] != nil {
      let readerId = UUID().uuidString
      photoReaders[readerId] = (sourceId, 0)
      result(readerId)
      return
    }
    guard let source = sources[sourceId] else {
      result(FlutterError(code: "unknown_source", message: "source \(sourceId) not found", details: nil))
      return
    }
    let openGeneration = generation
    ioQueue.async { [weak self] in
      let handle = try? FileHandle(forReadingFrom: source.url)
      DispatchQueue.main.async {
        guard let self else { return }
        guard openGeneration == self.generation, self.sources[sourceId] != nil else {
          // open 도중에 releaseAll이 돎: 방금 연 핸들은 등록 안 하고 바로 닫음
          try? handle?.close()
          result(FlutterError(code: "released", message: "source was released during open", details: nil))
          return
        }
        guard let handle else {
          result(FlutterError(code: "open_failed", message: "could not open \(sourceId)", details: nil))
          return
        }
        let readerId = UUID().uuidString
        self.readers[readerId] = handle
        result(readerId)
      }
    }
  }

  private func read(readerId: String, maxBytes: Int, result: @escaping FlutterResult) {
    guard maxBytes > 0, maxBytes <= 1024 * 1024 else {
      result(FlutterError(code: "bad_args", message: "invalid read size", details: nil))
      return
    }
    if let reader = photoReaders[readerId], let data = photos[reader.sourceId] {
      let end = min(reader.offset + maxBytes, data.count)
      photoReaders[readerId] = (reader.sourceId, end)
      result(end == reader.offset ? nil : FlutterStandardTypedData(bytes: data.subdata(in: reader.offset..<end)))
      return
    }
    guard let handle = readers[readerId] else {
      result(FlutterError(code: "unknown_reader", message: "reader \(readerId) not found", details: nil))
      return
    }
    ioQueue.async {
      let data = try? handle.read(upToCount: maxBytes)
      DispatchQueue.main.async {
        if let data, !data.isEmpty {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)  // EOF
        }
      }
    }
  }

  private func close(readerId: String?) {
    if let readerId { photoReaders.removeValue(forKey: readerId) }
    guard let readerId, let handle = readers.removeValue(forKey: readerId) else { return }
    ioQueue.async {
      try? handle.close()
    }
  }

  private func release(sourceId: String?) {
    if let sourceId {
      photos.removeValue(forKey: sourceId)
      photoReaders = photoReaders.filter { $0.value.sourceId != sourceId }
    }
    guard let sourceId, let source = sources.removeValue(forKey: sourceId) else { return }
    source.url.stopAccessingSecurityScopedResource()
  }

  private func releaseAll() {
    generation += 1
    photoProgress?.cancel()
    photoProgress = nil
    activePicker?.dismiss(animated: false)
    activePicker = nil
    let result = pendingPick
    pendingPick = nil
    result?([])
    photos.removeAll()
    photoReaders.removeAll()
    for (_, source) in sources {
      source.url.stopAccessingSecurityScopedResource()
    }
    sources.removeAll()
    let open = Array(readers.values)
    readers.removeAll()
    ioQueue.async {
      for handle in open { try? handle.close() }
    }
  }
}
