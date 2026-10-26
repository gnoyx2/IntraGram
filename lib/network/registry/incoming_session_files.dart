import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:intragram/core/private_dir.dart';

import 'package:path/path.dart' as p;

import 'package:intragram/network/file_streamer.dart'
    show TransferCleanupException;
import 'package:intragram/network/registry/incoming_path_resolver.dart';

// 이번 실행에서 .part를 만든 폴더와 받은 파일 경로 (RAM). 패닉 뒤 레지스트리가 새로 생겨도 남아야 해서 static
abstract final class IncomingSessionFiles {
  static final Set<String> _directories = <String>{};
  static final Set<String> _received = <String>{};

  // macOS 샌드박스는 고른 폴더 권한을 그 실행 동안만 줌: 보안 범위 북마크를 같이 적어 다음 실행에서 다시 엶
  static const _privacy = MethodChannel('intragram/privacy');

  @visibleForTesting
  static File? settingsFileForTesting;

  static int get receivedCount => _received.length;

  static void recordDirectory(String directory) => _directories.add(directory);

  static void recordReceived(String path) => _received.add(path);

  static Future<File> _settingsFile() async =>
      settingsFileForTesting ??
      File(p.join(await privateAppDir(), 'download_directories.json'));

  // 보관소와 따로인 앱 설정. .part를 만들기 전에 고른 폴더를 적어 둠 (크래시 뒤 정리용)
  static Future<void> rememberDirectory(
    String path, {
    File? settingsFile,
  }) async {
    final file = settingsFile ?? await _settingsFile();
    final bookmark = await _bookmark(path);
    final entries = {..._readDirectories(file), path: bookmark};
    final tmp = File('${file.path}.tmp');
    // 읽기~쓰기 사이에 await가 없어서 동시에 고른 폴더끼리 안 덮음
    tmp.writeAsStringSync(jsonEncode(entries), flush: true);
    tmp.renameSync(file.path);
    recordDirectory(path);
  }

  // 폴더 경로 → macOS 북마크(base64, 다른 OS는 null). 예전 형식(경로 목록)도 읽음.
  // 깨졌거나 못 읽으면 빈 목록 (설정 파일 하나 때문에 시작·저장이 막히면 안 됨)
  static Map<String, String?> _readDirectories(File file) {
    try {
      if (!file.existsSync()) return const {};
      final value = jsonDecode(file.readAsStringSync());
      final Map<String, String?> entries = switch (value) {
        final List<Object?> paths when paths.every((path) => path is String) =>
          {for (final path in paths.cast<String>()) path: null},
        final Map<String, Object?> map
            when map.values.every((bookmark) => bookmark is String?) =>
          map.cast<String, String?>(),
        _ => const {},
      };
      return entries.keys.every(p.isAbsolute) ? entries : const {};
    } on Object {
      return const {};
    }
  }

  // macOS만: 폴더를 고른 직후(아직 권한이 있을 때) 북마크를 만듦. 채널이 없으면 경로만 적음
  static Future<String?> _bookmark(String path) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return null;
    try {
      final data = await _privacy.invokeMethod<Uint8List>(
        'bookmarkDirectory',
        path,
      );
      return data == null ? null : base64Encode(data);
    } on Exception {
      return null;
    }
  }

  // 북마크가 가리키는 지금 경로(옮겨진 폴더면 새 위치). 접근은 앱이 끝날 때까지 열어 둠 (패닉 정리도 같은 폴더를 훑음)
  static Future<String?> _openBookmark(String? bookmark) async {
    if (bookmark == null || defaultTargetPlatform != TargetPlatform.macOS) {
      return null;
    }
    try {
      return await _privacy.invokeMethod<String>(
        'openBookmark',
        base64Decode(bookmark),
      );
    } on Exception {
      return null;
    }
  }

  // 패닉: 폴더 목록과 임시 파일을 지움
  static Future<void> deleteDirectorySettings({File? settingsFile}) async {
    final file = settingsFile ?? await _settingsFile();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (target.existsSync()) target.deleteSync();
    }
  }

  // 시작할 때 한 번만 복원 (패닉 정리는 이번 세션 목록만 씀)
  static Future<void> restoreDirectories({File? settingsFile}) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    final entries = _readDirectories(settingsFile ?? await _settingsFile());
    for (final MapEntry(key: path, value: bookmark) in entries.entries) {
      _directories.add(await _openBookmark(bookmark) ?? path);
    }
  }

  // 크래시로 남은 .intragram-*.part를 지움. 받는 전송이 없을 때만 부를 것 (시작 직후, 패닉에서 링크가 다 닫힌 뒤)
  static Future<int> sweepOrphanPartials([
    Iterable<String>? directories,
  ]) async {
    final targets =
        directories?.toSet() ??
        <String>{..._directories, ?await IncomingPathResolver.mobileSaveDir()};
    var deleted = 0;
    final failures = <Object>[];
    for (final path in targets) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) continue;
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is File && _partialName.hasMatch(p.basename(entry.path))) {
            try {
              await entry.delete();
              deleted++;
            } on FileSystemException catch (e) {
              failures.add(e);
            }
          }
        }
      } on FileSystemException catch (e) {
        failures.add(e);
      }
    }
    if (failures.isNotEmpty) throw TransferCleanupException(failures: failures);
    return deleted;
  }

  // 이번 세션에 받은 파일 삭제 (패닉 옵션). 못 지운 것만 목록에 남기고 모아서 던짐
  static Future<void> deleteReceived() async {
    final failures = <Object>[];
    for (final path in _received.toList()) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        _received.remove(path);
      } on FileSystemException catch (e) {
        failures.add(e);
      }
    }
    if (failures.isNotEmpty) {
      throw TransferCleanupException(failures: failures);
    }
  }

  // 패닉 끝에 경로 기록 자체도 RAM에서 지움
  static void forget() {
    _directories.clear();
    _received.clear();
  }
}

// IncomingPathResolver.reserveDestination이 만드는 임시 파셜 이름
final RegExp _partialName = RegExp(r'^\.intragram-.*\.part$');
