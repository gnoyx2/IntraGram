import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:intragram/core/app_settings.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';

// IP·스캔 연결 실패를 이유별 안내로 바꿈. iOS·macOS는 로컬 네트워크 권한이 꺼져도 응답 없음·경로 없음으로
// 보여서 그 확인과 설정 열기를 붙임
SnackBar connectFailureSnackBar(S s, PeerUnreachableReason reason) {
  final apple =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  final localNetwork =
      apple &&
      (reason == PeerUnreachableReason.noAnswer ||
          reason == PeerUnreachableReason.noRoute);
  final text = s.t(switch (reason) {
    PeerUnreachableReason.noAnswer => 'connect.noAnswer',
    PeerUnreachableReason.refused => 'connect.refused',
    PeerUnreachableReason.noRoute => 'connect.noRoute',
    PeerUnreachableReason.notIntragram => 'connect.notIntragram',
  });
  return SnackBar(
    content: Text(
      localNetwork ? '$text ${s.t('connect.localNetworkCheck')}' : text,
    ),
    duration: const Duration(seconds: 8),
    action: localNetwork && canOpenSettings(SettingsPane.localNetwork)
        ? SnackBarAction(
            label: s.t('settings.open'),
            onPressed: () => openSettings(SettingsPane.localNetwork),
          )
        : null,
  );
}
