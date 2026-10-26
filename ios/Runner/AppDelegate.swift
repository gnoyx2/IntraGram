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
  private var privacyCovers: [UIView] = []
  private var appTransitioningInactive = false
  private var inactiveScenes: Set<ObjectIdentifier> = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 스크린샷은 못 막지만 알릴 수는 있음 (텔레그램 비밀 채팅과 같음). 앱 전역 알림이라 씬·윈도우와 상관없음
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    // 앱 전환기 스냅샷에 대화가 안 찍히게 비활성 직전 불투명 커버로 덮음 (씬 라이프사이클이라 applicationWillResignActive 대신 알림으로 받음)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillResign),
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
    NotificationCenter.default.addObserver(
      self, selector: #selector(reduceTransparencyChanged),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil
    )
    for name in [UIScene.didActivateNotification, UIWindow.didBecomeVisibleNotification] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowSceneChanged(_:)), name: name, object: nil
      )
    }
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

  // iOS 27.1+ 접힘선·힌지 상태의 마지막 값 (DisplayRegions.swift). Dart가 뜨기 전에 잰 값도 남겨 둠
  private static var displayRegions: [String: Any]?

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
    case "reduceTransparency":
      result(UIAccessibility.isReduceTransparencyEnabled)
    case "displayRegions":
      // nil이면 접힘선을 안 알려 주는 iOS라 Dart가 화면 크기로 짐작함. 지원하면 아직 못 쟀어도 빈 목록
      if #available(iOS 27.1, *) {
        result(displayRegions ?? ["status": 0, "regions": [[Double]]()])
      } else {
        result(nil)
      }
    case "clipboardKinds":
      // hasImages는 내용을 안 읽어서 붙여넣기 허용 창이 안 뜸 (파일 붙여넣기는 데스크톱만)
      result(["image": UIPasteboard.general.hasImages, "files": false])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func showPrivacyCover() {
    for scene in windowScenes {
      for window in scene.windows { cover(window) }
    }
  }

  @objc private func applicationWillResign() {
    appTransitioningInactive = true
    showPrivacyCover()
  }

  private func cover(_ window: UIWindow) {
    if let existing = privacyCovers.first(where: { $0.superview === window }) {
      existing.frame = window.bounds
      window.bringSubviewToFront(existing)
      return
    }
    let cover = UIView()
    cover.backgroundColor = .black
    cover.isOpaque = true
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // 미러링·녹화로 가린 거면 멈춘 게 아니라는 걸 알려 줌 (앱 전환 스냅샷엔 문구 없음)
    if UIScreen.screens.contains(where: { $0.isCaptured }) { addCaptureNotice(to: cover) }
    window.addSubview(cover)
    privacyCovers.append(cover)
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard let scene = notification.object as? UIWindowScene else { return }
    inactiveScenes.insert(ObjectIdentifier(scene))
    for window in scene.windows { cover(window) }
  }

  @objc private func windowSceneChanged(_ notification: Notification) {
    if notification.name == UIScene.didActivateNotification,
      let scene = notification.object as? UIWindowScene {
      inactiveScenes.remove(ObjectIdentifier(scene))
    }
    syncPrivacyCovers()
    attachRegionProbes()
  }

  // Flutter 창마다 접힘선 재는 뷰를 한 번 붙임 (맨 밑, 터치·접근성 없음)
  private func attachRegionProbes() {
    guard #available(iOS 27.1, *) else { return }
    for scene in windowScenes {
      for window in scene.windows
      where window.rootViewController is FlutterViewController
        && !window.subviews.contains(where: { $0 is DisplayRegionProbe }) {
        let probe = DisplayRegionProbe { [weak self] state in
          AppDelegate.displayRegions = state
          self?.privacyChannel?.invokeMethod("onDisplayRegions", arguments: state)
        }
        probe.frame = window.bounds
        window.insertSubview(probe, at: 0)
      }
    }
  }

  private func syncPrivacyCovers() {
    let captured = UIScreen.screens.contains(where: { $0.isCaptured })
    for scene in windowScenes {
      for window in scene.windows {
        if captured || appTransitioningInactive
          || UIApplication.shared.applicationState != .active
          || inactiveScenes.contains(ObjectIdentifier(scene))
          || scene.activationState != .foregroundActive {
          cover(window)
        } else {
          privacyCovers.filter { $0.superview === window }.forEach { $0.removeFromSuperview() }
        }
      }
    }
    privacyCovers.removeAll { $0.superview == nil }
  }

  @objc private func reduceTransparencyChanged() {
    privacyChannel?.invokeMethod(
      "onReduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled
    )
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
    // 녹화가 시작되면 문구 있는 가림막으로 바꾸고, 끝나면 활성 창은 풀고 비활성 창은 문구 없는 가림막으로 바꿈
    // (비활성 중에 끝나도 '녹화 중' 문구가 앱 전환기 스냅샷에 남지 않게 매번 새로 덮음)
    hideCoverNow()
    syncPrivacyCovers()
  }

  @objc private func hidePrivacyCover() {
    if UIApplication.shared.applicationState == .active { appTransitioningInactive = false }
    guard !UIScreen.screens.contains(where: { $0.isCaptured }) else {
      showPrivacyCover()
      return
    }
    syncPrivacyCovers()
  }

  private func hideCoverNow() {
    privacyCovers.forEach { $0.removeFromSuperview() }
    privacyCovers.removeAll()
  }

  private var windowScenes: [UIWindowScene] {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
  }

  @objc private func userDidTakeScreenshot() {
    screenshotChannel?.invokeMethod("onScreenshot", arguments: nil)
  }
}
