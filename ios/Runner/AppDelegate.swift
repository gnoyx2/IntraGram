import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotChannel: FlutterMethodChannel?
  private var memoryFileSource: MemoryFileSource?
  private var voicePlayer: VoicePlayer?
  private var fileProtectionChannel: FlutterMethodChannel?
  private var privacyChannel: FlutterMethodChannel?
  private var privacyCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 스크린샷은 막을 수 없지만 알릴 수는 있음 (텔레그램 비밀 채팅과 같음).
    // 앱 전역 알림이라 씬/윈도우와 무관.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    // 앱 전환기 스냅샷에 대화가 안 찍히게 비활성 직전 불투명 커버로 덮음.
    // 씬 라이프사이클이라 applicationWillResignActive 대신 알림으로 받음
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(showPrivacyCover),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(hidePrivacyCover),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(captureStateChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IntraGramScreenshot")
    if let messenger = registrar?.messenger() {
      screenshotChannel = FlutterMethodChannel(
        name: "intragram/screenshot",
        binaryMessenger: messenger
      )
      memoryFileSource = MemoryFileSource(messenger: messenger)
      voicePlayer = VoicePlayer(messenger: messenger)
      fileProtectionChannel = FlutterMethodChannel(
        name: "intragram/file_protection",
        binaryMessenger: messenger
      )
      fileProtectionChannel?.setMethodCallHandler(AppDelegate.protectFile)
      privacyChannel = FlutterMethodChannel(
        name: "intragram/privacy",
        binaryMessenger: messenger
      )
      privacyChannel?.setMethodCallHandler(AppDelegate.handlePrivacy)
    }
  }

  // vault.json/identity.json과 그 폴더: iCloud/Finder 백업 제외 + 잠금 중엔 못 읽게
  private static func protectFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "protect", let path = call.arguments as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    do {
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: path
      )
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      result(nil)
    } catch {
      result(FlutterError(code: "protect_failed", message: error.localizedDescription, details: nil))
    }
  }

  // 마지막 copySensitive 직후의 changeCount. 내용을 안 읽고 우리 복사본인지 비교함
  // (다른 앱 내용을 읽으면 iOS 16+ 붙여넣기 허용 팝업이 뜸)
  private static var sensitiveChangeCount: Int?

  // copySensitive: 이 기기에서만 (Universal Clipboard로 다른 기기에 안 넘어감), 60초 뒤 OS가 만료
  private static func handlePrivacy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "copySensitive":
      let text = call.arguments as? String ?? ""
      UIPasteboard.general.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]
      )
      sensitiveChangeCount = UIPasteboard.general.changeCount
      result(nil)
    case "clearIfOwn":
      let own = sensitiveChangeCount == UIPasteboard.general.changeCount
      if own { UIPasteboard.general.items = [] }
      sensitiveChangeCount = nil
      result(own)
    case "clearClipboard":
      UIPasteboard.general.items = []
      sensitiveChangeCount = nil
      result(nil)
    case "isPad":
      result(UIDevice.current.userInterfaceIdiom == .pad)
    case "clipboardKinds":
      // hasImages는 내용을 안 읽어서 붙여넣기 허용 창이 안 뜸 (파일 붙여넣기는 데스크톱만)
      result(["image": UIPasteboard.general.hasImages, "files": false])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func showPrivacyCover() {
    guard privacyCover == nil, let window = keyWindow() else { return }
    let cover = UIView()
    cover.backgroundColor = .black
    cover.isOpaque = true
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // 미러링·녹화로 가린 거면 멈춘 게 아니라는 걸 알려 줌 (앱 전환 스냅샷엔 문구 없음)
    if UIScreen.screens.contains(where: { $0.isCaptured }) { addCaptureNotice(to: cover) }
    window.addSubview(cover)
    privacyCover = cover
  }

  private func addCaptureNotice(to cover: UIView) {
    let korean = Locale.preferredLanguages.first?.hasPrefix("ko") == true
    let label = UILabel()
    label.text =
      korean
      ? "화면 공유·녹화 중이라 대화를 가렸어요"
      : "Chats are hidden while the screen is shared or recorded"
    label.textColor = .white
    label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    let mark = UIImageView(image: UIImage(named: "LaunchImage"))
    mark.contentMode = .scaleAspectFit
    let stack = UIStackView(arrangedSubviews: [mark, label])
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      stack.widthAnchor.constraint(lessThanOrEqualTo: cover.widthAnchor, constant: -48),
      mark.widthAnchor.constraint(equalToConstant: 96),
      mark.heightAnchor.constraint(equalToConstant: 96),
    ])
  }

  @objc private func captureStateChanged() {
    if UIScreen.screens.contains(where: { $0.isCaptured }) {
      // 앱 전환 때 덮은 문구 없는 가림막이면 문구 있는 것으로 바꿈
      hideCoverNow()
      showPrivacyCover()
    } else if UIApplication.shared.applicationState == .active {
      hidePrivacyCover()
    }
  }

  @objc private func hidePrivacyCover() {
    guard !UIScreen.screens.contains(where: { $0.isCaptured }) else {
      showPrivacyCover()
      return
    }
    hideCoverNow()
  }

  private func hideCoverNow() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  @objc private func userDidTakeScreenshot() {
    screenshotChannel?.invokeMethod("onScreenshot", arguments: nil)
  }
}
