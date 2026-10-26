import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// 비공개 파일 자리. Documents는 iOS 파일 앱·iCloud 백업에 잡혀서 Application Support 밑에 둠 (받은 파일은 Documents/IntraGram)
const List<String> _privateFiles = [
  'vault.json',
  'identity.json',
  'download_directories.json',
];
const MethodChannel _protectChannel = MethodChannel(
  'intragram/file_protection',
);

Future<String>? _cached;

Future<String> privateAppDir() => _cached ??= _resolve().then(
  (dir) => dir,
  onError: (Object e, StackTrace s) {
    _cached = null; // 실패를 캐시하면 다음에도 계속 실패함
    Error.throwWithStackTrace(e, s);
  },
);

Future<String> _resolve() async {
  // Windows 지원 폴더는 %APPDATA%(로밍)라 도메인 프로필이면 로그오프 때 서버로 복사됨: %LOCALAPPDATA%에 두고 예전 파일은 옮김
  final support = Platform.isWindows
      ? await getApplicationCacheDirectory()
      : await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'IntraGram'));
  await dir.create(recursive: true);
  await _migrateFromDocuments(dir.path);
  if (Platform.isWindows) {
    final roaming = await getApplicationSupportDirectory();
    await migratePrivateFiles(
      from: p.join(roaming.path, 'IntraGram'),
      to: dir.path,
    );
  }
  // 폴더에 걸어 두면 나중에 생기는 .tmp·rename 결과도 속성을 물려받음
  await _protect(dir.path);
  for (final name in _privateFiles) {
    final file = File(p.join(dir.path, name));
    if (file.existsSync()) await _protect(file.path);
  }
  return dir.path;
}

Future<void> _migrateFromDocuments(String target) async {
  final docs = await getApplicationDocumentsDirectory();
  await migratePrivateFiles(from: p.join(docs.path, 'IntraGram'), to: target);
}

// 옛 위치 파일을 옮기고 원본은 지움. 복사가 끝나야 지워서 도중에 비정상 종료돼도 한쪽엔 남음. 새 위치에 있으면 최신본이라 옛 파일만 지움
@visibleForTesting
Future<void> migratePrivateFiles({
  required String from,
  required String to,
}) async {
  if (p.equals(from, to)) return;
  for (final name in _privateFiles) {
    final old = File(p.join(from, name));
    final moved = File(p.join(to, name));
    if (old.existsSync() && !moved.existsSync()) {
      final tmp = await old.copy('${moved.path}.tmp');
      await tmp.rename(moved.path);
    }
    for (final stale in [old, File('${old.path}.tmp')]) {
      if (stale.existsSync()) await stale.delete();
    }
  }
}

// iOS만: 백업 제외 + NSFileProtectionComplete (다른 OS는 매니페스트·권한으로 막음)
Future<void> _protect(String path) async {
  if (!Platform.isIOS) return;
  await _protectChannel.invokeMethod<void>('protect', path);
}
