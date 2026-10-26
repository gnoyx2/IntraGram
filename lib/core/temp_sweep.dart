import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 시작·패닉 때 앱 전용 임시·캐시 폴더를 비움: 플러그인이 남긴 사본(공유 시트·파일 선택·드래그 등)이 평문으로 안 남게.
// Windows·Linux 임시 폴더는 공용이라 안 건드림. 못 지운 게 있으면 끝까지 돈 뒤 던짐
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

// iOS·macOS의 path_provider 임시 폴더는 Caches라 tmp/(systemTemp)에 쓰는 플러그인 몫도 같이 비움
@visibleForTesting
List<Directory> tempDirsFor(Directory pluginTemp, {required bool apple}) => [
  pluginTemp,
  if (apple) Directory.systemTemp,
];

// macOS는 샌드박스일 때만 tmp/가 이 앱 것 (아니면 사용자 공용 $TMPDIR)
@visibleForTesting
bool tempIsAppPrivate(String os, Map<String, String> env) => switch (os) {
  'ios' || 'android' => true,
  'macos' => env.containsKey('APP_SANDBOX_CONTAINER_ID'),
  _ => false,
};
