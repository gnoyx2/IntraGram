import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// 거부한 권한을 다시 켤 OS 설정 화면
enum SettingsPane { microphone, camera, localNetwork }

const MethodChannel _privacy = MethodChannel('intragram/privacy');

// 이 기기에서 그 설정 화면을 앱이 직접 열 수 있는지. 못 열면 호출부는 경로 문구만 보여 줌
bool canOpenSettings(SettingsPane pane) =>
    defaultTargetPlatform == TargetPlatform.android ||
    settingsUriFor(defaultTargetPlatform, pane) != null;

Future<bool> openSettings(SettingsPane pane) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 앱 정보 화면(권한 항목이 거기 있음). ACTION_APPLICATION_DETAILS_SETTINGS라 네이티브로 엶
      return await _privacy.invokeMethod<bool>('openAppSettings') ?? false;
    }
    final uri = settingsUriFor(defaultTargetPlatform, pane);
    if (uri == null) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}

// iOS는 앱별 설정 화면(로컬 네트워크·마이크·카메라 스위치가 다 있음), macOS는 개인정보 보호의 해당 항목,
// Windows는 마이크·카메라 개인정보 화면, 로컬 네트워크 자리엔 네트워크 프로필(개인/공용) 화면
// (Windows엔 로컬 네트워크 권한이 없고, 새 Wi-Fi가 공용이면 방화벽이 들어오는 연결을 막음). Linux는 열 화면이 없음
@visibleForTesting
Uri? settingsUriFor(TargetPlatform os, SettingsPane pane) => switch (os) {
  TargetPlatform.iOS => Uri.parse('app-settings:'),
  TargetPlatform.macOS => Uri.parse(
    'x-apple.systempreferences:com.apple.preference.security?'
    '${switch (pane) {
      SettingsPane.microphone => 'Privacy_Microphone',
      SettingsPane.camera => 'Privacy_Camera',
      SettingsPane.localNetwork => 'Privacy_LocalNetwork',
    }}',
  ),
  TargetPlatform.windows => switch (pane) {
    SettingsPane.microphone => Uri.parse('ms-settings:privacy-microphone'),
    SettingsPane.camera => Uri.parse('ms-settings:privacy-webcam'),
    SettingsPane.localNetwork => Uri.parse('ms-settings:network-status'),
  },
  TargetPlatform.android ||
  TargetPlatform.fuchsia ||
  TargetPlatform.linux => null,
};
