import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 시작 및 패닉 시 앱 전용 임시·캐시 디렉터리를 비움 (플러그인이 남긴 공유 시트·파일 선택·드래그 등의 사본이 평문으로 남지 않게 함).
// Windows·Linux 임시 폴더는 공용 경로라 정리 대상에서 제외함. 삭제 실패 항목이 있으면 전체 순회 완료 후 예외를 발생시킴
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

// macOS는 샌드박스일 때만 tmp/가 앱 전용 경로임 (아니면 사용자 공용 $TMPDIR)
@visibleForTesting
bool tempIsAppPrivate(String os, Map<String, String> env) => switch (os) {
  'ios' || 'android' => true,
  'macos' => env.containsKey('APP_SANDBOX_CONTAINER_ID'),
  _ => false,
};
