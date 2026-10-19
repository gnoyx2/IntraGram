import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_settings.dart';

// 권한 거부 안내의 "설정 열기"가 플랫폼마다 맞는 화면으로 감
void main() {
  test('iOS opens the app page that holds every permission switch', () {
    for (final pane in SettingsPane.values) {
      expect(
        settingsUriFor(TargetPlatform.iOS, pane).toString(),
        'app-settings:',
      );
    }
  });

  test('macOS opens the matching privacy pane', () {
    expect(
      settingsUriFor(
        TargetPlatform.macOS,
        SettingsPane.localNetwork,
      ).toString(),
      endsWith('?Privacy_LocalNetwork'),
    );
    expect(
      settingsUriFor(TargetPlatform.macOS, SettingsPane.microphone).toString(),
      endsWith('?Privacy_Microphone'),
    );
    expect(
      settingsUriFor(TargetPlatform.macOS, SettingsPane.camera)!.scheme,
      'x-apple.systempreferences',
    );
  });

  test('Windows has panes for the microphone and camera only', () {
    expect(
      settingsUriFor(
        TargetPlatform.windows,
        SettingsPane.microphone,
      ).toString(),
      'ms-settings:privacy-microphone',
    );
    expect(
      settingsUriFor(TargetPlatform.windows, SettingsPane.camera).toString(),
      'ms-settings:privacy-webcam',
    );
    // Windows엔 로컬 네트워크 권한이 없어 네트워크 프로필(개인/공용) 화면을 엶
    expect(
      settingsUriFor(
        TargetPlatform.windows,
        SettingsPane.localNetwork,
      ).toString(),
      'ms-settings:network-status',
    );
    expect(
      settingsUriFor(TargetPlatform.linux, SettingsPane.microphone),
      isNull,
    );
  });
}
