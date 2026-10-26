import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

// 거부한 권한을 다시 켤 OS 설정 화면
enum SettingsPane { microphone, camera, localNetwork }

const MethodChannel _privacy = MethodChannel('intragram/privacy');

// 못 열면 호출부는 경로 문구만 보여 줌
bool canOpenSettings(SettingsPane pane) =>
    defaultTargetPlatform == TargetPlatform.android ||
    settingsUriFor(defaultTargetPlatform, pane) != null;

Future<bool> openSettings(SettingsPane pane) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 앱 정보 화면(권한이 거기 있음)은 인텐트라 네이티브로 엶
      return await _privacy.invokeMethod<bool>('openAppSettings') ?? false;
    }
    final uri = settingsUriFor(defaultTargetPlatform, pane);
    if (uri == null) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}

// iOS는 앱 설정 화면(스위치가 다 있음), macOS는 개인정보 보호 해당 항목, Windows는 마이크·카메라 화면이고
// 로컬 네트워크 자리엔 네트워크 프로필 화면 (새 Wi-Fi가 공용이면 방화벽이 들어오는 연결을 막아서). Linux는 열 화면 없음
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
