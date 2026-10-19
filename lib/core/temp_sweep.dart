import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 앱 시작과 패닉 때 임시·캐시 폴더를 비움. 플러그인이 만든 사본(공유 시트용 사본, 파일 선택 사본,
// macOS 드래그 파일 프로미스, 예전 버전이 남긴 음성 캐시 등)이 평문으로 남지 않게 함
// 이 앱 것인 임시 폴더(iOS·Android, 샌드박스 macOS)만 통째로 비움. Windows·Linux 임시 폴더는
// 시스템 공용이라 안 건드림 (거기 쓰는 pasteboard 사본은 플러그인이 읽자마자 지움)
// 못 지운 게 있으면 끝까지 시도한 뒤 FileSystemException으로 알림 (패닉은 실패 단계로 표시)
Future<void> sweepAppTemp({List<Directory>? tempDirs, bool? appPrivate}) async {
  final private =
      appPrivate ??
      tempIsAppPrivate(Platform.operatingSystem, Platform.environment);
  if (!private) return;
  final dirs =
      tempDirs ??
      tempDirsFor(
        await getTemporaryDirectory(),
        apple: Platform.isIOS || Platform.isMacOS,
      );
  final failed = <String>[];
  for (final dir in dirs) {
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        failed.add(p.basename(entity.path));
      }
    }
  }
  if (failed.isNotEmpty) {
    throw FileSystemException('could not remove ${failed.length} temp entries');
  }
}

// path_provider 임시 폴더는 iOS·macOS에서 Caches라, tmp/(NSTemporaryDirectory = Dart의 systemTemp)에
// 쓰는 플러그인(desktop_drop, file_picker, 예전 AVPlayer 캐시)도 같이 비움
@visibleForTesting
List<Directory> tempDirsFor(Directory pluginTemp, {required bool apple}) => [
  pluginTemp,
  if (apple) Directory.systemTemp,
];

// macOS는 샌드박스일 때만 tmp/가 이 앱 컨테이너 것 (비샌드박스면 사용자 공용 $TMPDIR)
@visibleForTesting
bool tempIsAppPrivate(String os, Map<String, String> env) => switch (os) {
  'ios' || 'android' => true,
  'macos' => env.containsKey('APP_SANDBOX_CONTAINER_ID'),
  _ => false,
};
