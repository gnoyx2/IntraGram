import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // 별도 패널·시트·전체 화면에도 기존 공유 제한을 적용함. update()는 창이 처음 보이기 전과 이벤트 루프마다
    // 불려서(Apple NSWindow.update 문서) 새 창도 표시 전에 잡힘. 이동·타일링은 sharingType을 안 바꿔서 따로 안 봄
    for name in [NSWindow.didUpdateNotification, NSWindow.didEnterFullScreenNotification,
                 NSWindow.didExitFullScreenNotification] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(protectWindow(_:)), name: name, object: nil)
    }
    NSApp.windows.forEach(protect)
  }

  @objc private func protectWindow(_ notification: Notification) {
    if let window = notification.object as? NSWindow { protect(window) }
  }

  private func protect(_ window: NSWindow) {
    // sharingType는 최신 ScreenCaptureKit의 캡처 차단을 보장하지 않는 레거시 힌트임.
    // 이벤트마다 불리므로 이미 막힌 창은 읽기만 하고 넘어감
    if window.sharingType != .none { window.sharingType = .none }
    if let activity = window.userActivity {
      activity.invalidate()
      window.userActivity = nil
    }
    window.childWindows?.forEach(protect)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
