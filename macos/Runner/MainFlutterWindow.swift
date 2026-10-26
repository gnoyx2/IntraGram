import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var screenshotChannel: FlutterMethodChannel?
  private var screenshotQuery: NSMetadataQuery?
  private var voicePlayer: VoicePlayer?
  private var privacyChannel: FlutterMethodChannel?
  private var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    self.sharingType = .none
    let flutterViewController = FlutterViewController()
    // 첫 프레임 전엔 FlutterView가 기본 검정이라 라이트 모드에서 검은 창이 번쩍임: 외형별 앱 배경색
    flutterViewController.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x0D / 255, green: 0x0F / 255, blue: 0x14 / 255, alpha: 1)
        : .white
    }
    self.backgroundColor = flutterViewController.backgroundColor
    self.contentViewController = flutterViewController

    // 420×560은 두 줄 채팅 앱바 제목과 오른쪽 액션, 오프라인 배너, 말풍선 3개, 입력창이 글자 배율 1.0에서 안 찌그러지는 최소치
    self.minSize = NSSize(width: 420, height: 560)

    // setFrameAutosaveName은 같은 이름으로 저장된 프레임이 있으면 바로 복원해서, 저장된 게 없을 때(첫 실행)만
    // 기본 크기와 가운데 정렬을 씀 (안 그러면 실행할 때마다 방금 복원한 위치·크기를 기본값으로 덮어씀)
    let autosaveName = "MainWindow"
    let hasSavedFrame =
      UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
    self.setFrameAutosaveName(autosaveName)
    if !hasSavedFrame {
      self.setContentSize(NSSize(width: 1100, height: 760))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    screenshotChannel = FlutterMethodChannel(
      name: "intragram/screenshot",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    startWatchingScreenshots()
    voicePlayer = VoicePlayer(messenger: flutterViewController.engine.binaryMessenger)
    privacyChannel = FlutterMethodChannel(
      name: "intragram/privacy",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    privacyChannel?.setMethodCallHandler(MainFlutterWindow.handlePrivacy)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityChanged(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
    )
    menuChannel = FlutterMethodChannel(
      name: "intragram/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  // 메뉴 막대(MainMenu.xib, First Responder 액션) 명령은 Dart(AppCommands)가 단축키와 같은 길로 처리
  @objc func showSettings(_ sender: Any?) { menuChannel?.invokeMethod("settings", arguments: nil) }
  @objc func newConnection(_ sender: Any?) {
    menuChannel?.invokeMethod("newConnection", arguments: nil)
  }
  @objc func closePage(_ sender: Any?) { menuChannel?.invokeMethod("close", arguments: nil) }

  @objc func findMessages(_ sender: Any?) { menuChannel?.invokeMethod("search", arguments: nil) }
  @objc func increaseTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: 1)
  }
  @objc func decreaseTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: -1)
  }
  @objc func resetTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: 0)
  }

  @objc private func accessibilityChanged(_ notification: Notification) {
    let workspace = NSWorkspace.shared
    privacyChannel?.invokeMethod(
      "onReduceTransparencyChanged", arguments: workspace.accessibilityDisplayShouldReduceTransparency)
    privacyChannel?.invokeMethod(
      "onReduceMotionChanged", arguments: workspace.accessibilityDisplayShouldReduceMotion)
    privacyChannel?.invokeMethod(
      "onHighContrastChanged", arguments: workspace.accessibilityDisplayShouldIncreaseContrast)
  }

  override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
    childWin.sharingType = .none
    super.addChildWindow(childWin, ordered: place)
  }

  override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
    sheetWindow.sharingType = .none
    super.beginSheet(sheetWindow, completionHandler: handler)
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
    screenshotQuery?.stop()
  }

  // 마지막 copySensitive 직후의 changeCount. 내용을 안 읽고 우리 복사본인지 비교함
  private static var sensitiveChangeCount: Int?

  // copySensitive: 이 Mac에서만(.currentHostOnly라 Universal Clipboard로 다른 기기에 안 넘어감), 클립보드
  // 관리자가 기록하지 않게 nspasteboard.org의 Concealed 표식을 같이 둠
  // clipboardKinds: 붙여넣기 버튼용으로 형식 목록만 봄 (내용을 읽으면 macOS 15.4+ 붙여넣기 경고가 뜰 수 있음)
  private static func handlePrivacy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let board = NSPasteboard.general
    switch call.method {
    case "copySensitive":
      _ = board.prepareForNewContents(with: .currentHostOnly)
      board.setString(call.arguments as? String ?? "", forType: .string)
      board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
      sensitiveChangeCount = board.changeCount
      result(nil)
    case "clearIfOwn":
      let own = sensitiveChangeCount == board.changeCount
      if own { board.clearContents() }
      sensitiveChangeCount = nil
      result(own)
    case "clearClipboard":
      board.clearContents()
      sensitiveChangeCount = nil
      result(nil)
    case "revealFile":
      // Finder에서 받은 파일을 선택 상태로 (프로세스 안이라 고른 폴더의 샌드박스 권한이 그대로 먹음)
      guard let path = call.arguments as? String else { return result(false) }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      result(true)
    case "bookmarkDirectory":
      // 샌드박스는 고른 폴더 권한을 이번 실행 동안만 줌. 크래시로 남은 .part를 다음 실행에서 지우려고 북마크를 둠
      guard let path = call.arguments as? String,
        let data = try? URL(fileURLWithPath: path, isDirectory: true).bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      else { return result(nil) }
      result(FlutterStandardTypedData(bytes: data))
    case "openBookmark":
      // 접근은 앱이 끝날 때까지 둠 (패닉 정리도 같은 폴더를 다시 훑음)
      // stale(옮겨진 폴더)이어도 그대로 씀: 그 폴더를 다시 고르면 새 북마크로 적힘
      var stale = false
      guard let bookmark = call.arguments as? FlutterStandardTypedData,
        let url = try? URL(
          resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI],
          relativeTo: nil, bookmarkDataIsStale: &stale)
      else { return result(nil) }
      _ = url.startAccessingSecurityScopedResource()
      result(url.path)
    case "reduceTransparency":
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    case "highContrast":
      result(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    case "reduceMotion":
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    case "clipboardKinds":
      let types = (board.types ?? []).map(\.rawValue)
      result([
        "image": types.contains { NSImage.imageTypes.contains($0) },
        "files": types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // macOS엔 iOS의 userDidTakeScreenshotNotification 같은 알림이 없어서, screencapture(Cmd+Shift+3/4/5)가 저장하는
  // 파일마다 Spotlight가 붙이는 kMDItemIsScreenCapture 메타데이터를 NSMetadataQuery로 실시간 감시함.
  // 샌드박스에서도 되는 표준 기법 (파일 내용이 아니라 메타데이터 검색이라 files.user-selected 권한이 필요 없음)
  private func startWatchingScreenshots() {
    let query = NSMetadataQuery()
    query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
    query.searchScopes = [NSMetadataQueryLocalComputerScope]
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onScreenshotQueryUpdate(_:)),
      name: .NSMetadataQueryDidUpdate,
      object: query
    )
    query.start()
    screenshotQuery = query
  }

  // DidUpdate는 새로 잡힌 파일뿐 아니라 전에 잡힌 파일이 바뀌거나 지워질 때도 옴: Added만 걸러서 앱이 도는 중에
  // 방금 찍힌 스크린샷에만 반응함 (옛 스크린샷을 지우기만 해도 알림이 뜨는 오탐 방지)
  @objc private func onScreenshotQueryUpdate(_ notification: Notification) {
    let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]
    guard let added, !added.isEmpty else { return }
    screenshotChannel?.invokeMethod("onScreenshot", arguments: nil)
  }
}
