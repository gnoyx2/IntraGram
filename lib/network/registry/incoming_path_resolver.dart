import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:intragram/core/native_open.dart';
import 'package:intragram/core/path_safety.dart';
import 'package:intragram/core/path_safety_names.dart'
    show kMaxBasenameBytes, truncateUtf8;
import 'package:intragram/core/secure_bytes.dart' show generateSecureToken;
import 'package:intragram/network/file_streamer.dart'
    show TransferCleanupException;
import 'package:intragram/network/registry/incoming_session_files.dart';

// 받은 파일의 디스크 목적지: 폴더 고르기(이번 실행 동안 기억)와 이름 충돌 처리. 경로 탈출 방어는 core/path_safety.dart
class IncomingPathResolver {
  IncomingPathResolver({this.chooseDirectory});

  // 저장 폴더를 고르는 seam (프로덕션은 null이라 플랫폼 로직, 테스트는 임시 폴더)
  final Future<String?> Function(String suggestedName)? chooseDirectory;

  String? _sessionSaveDir;

  // 처음 고른 폴더를 이번 실행 동안 기억함 (RAM): 연달아 받거나 자동 수락할 때 다시 안 물음
  Future<String?> saveDir(String suggestedName) async {
    final chooser = chooseDirectory;
    if (chooser != null) return chooser(suggestedName);
    final cached = _sessionSaveDir;
    if (cached != null) return cached;
    final picked = await defaultChooseDirectory(suggestedName);
    _sessionSaveDir = picked;
    return picked;
  }

  void clear() {
    _sessionSaveDir = null;
  }

  // 데스크톱은 폴더 대화상자, 모바일은 앱 문서 폴더의 IntraGram/. 음성 수동 저장 버튼도 써서 public
  static Future<String?> defaultChooseDirectory(String suggestedName) async {
    final mobileDir = await mobileSaveDir();
    if (mobileDir != null) return mobileDir;
    // 창 제목은 언어 상관없는 파일 이름만 (네트워크 계층엔 번역이 없음)
    final String? picked;
    try {
      picked = await FilePicker.getDirectoryPath(dialogTitle: suggestedName);
    } on Exception catch (error) {
      throw PickerUnavailableException(error);
    }
    if (picked != null) await IncomingSessionFiles.rememberDirectory(picked);
    return picked;
  }

  // 모바일 고정 저장 폴더 (데스크톱은 null)
  static Future<String?> mobileSaveDir() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return null;
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'IntraGram');
  }

  // 이번 시도 전용 .part를 exclusive create로 예약. 같은 이름을 동시에 받는 다른 시도와 안 섞이게 이름에 attempt를 넣고
  // 최종 이름은 commitDestination이 정함. 폴더는 심링크를 푼 진짜 경로 기준이고 name이 그 밖으로 못 나가는 걸 미리 확인함.
  // attemptId는 상대가 보낸 값이라 영숫자·-·_만 남겨 자르고 로컬 난수를 붙임
  static Future<({File partial, String finalName})> reserveDestination({
    required String directory,
    required String name,
    required String attemptId,
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);
    final canonicalDirectory = await dir.resolveSymbolicLinks();
    final finalName = safeBasename(name);
    resolveWithin(canonicalDirectory, finalName);
    final boundedAttempt = truncateUtf8(
      attemptId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
      kMaxAttemptSuffixBytes,
    );
    final localSuffix = generateSecureToken().replaceAll(
      RegExp(r'[^A-Za-z0-9]'),
      '',
    );
    final partial = File(
      p.join(
        canonicalDirectory,
        '.intragram-$boundedAttempt-$localSuffix.part',
      ),
    );
    await partial.create(exclusive: true);
    IncomingSessionFiles.recordDirectory(canonicalDirectory);
    return (partial: partial, finalName: finalName);
  }

  // 그 이름에 뭐라도(파일·폴더·링크) 이미 있을 때만 충돌. Windows는 폴더 위 create가 EEXIST 말고
  // 접근 거부로 실패해서 실제 자리를 다시 봄
  @visibleForTesting
  static bool isNameCollision(String candidate, OSError? error) =>
      FileSystemEntity.typeSync(candidate, followLinks: false) !=
          FileSystemEntityType.notFound ||
      error?.errorCode == _kFileExistsErrno;

  // 끝난 .part를 finalName으로 커밋 (성공한 전송만). 최종 이름을 exclusive create로 먼저 잡고 충돌하면 (n)을 붙여 다시,
  // 잡은 자리에 rename함 (파일 위 rename은 원자적으로 덮음). 진짜 이름 충돌만 다음 이름으로 넘기고 나머진 바로 던짐
  // (아니면 권한 거부·디스크 꽉 참이 이름만 바꾸며 100번 돎). rename이 실패하면 이번에 만든 빈 자리만 지움 (사용자 파일은 절대 안 지움)
  static Future<String> commitDestination(
    File partial,
    String finalName,
  ) async {
    final dir = p.dirname(partial.path);
    final ext = p.extension(finalName);
    final stem = p.basenameWithoutExtension(finalName);
    var candidate = p.join(dir, finalName);
    var attempts = 0;
    while (true) {
      attempts++;
      if (attempts > kMaxCommitAttempts) {
        throw StateError(
          'commitDestination: exhausted $kMaxCommitAttempts naming '
          'attempts under "$dir"',
        );
      }
      final placeholder = File(candidate);
      try {
        await placeholder.create(exclusive: true);
      } on FileSystemException catch (e) {
        // 그 외(권한 거부, 디스크 꽉 참, 상위 디렉터리 소실 등)는 이름을 바꿔도 안 풀리므로 즉시 던짐
        if (!isNameCollision(candidate, e.osError)) rethrow;
        final suffix = ' ($attempts)';
        final budget = kMaxBasenameBytes - utf8.encode('$suffix$ext').length;
        candidate = p.join(dir, '${truncateUtf8(stem, budget)}$suffix$ext');
        continue;
      }
      try {
        await partial.rename(candidate);
        IncomingSessionFiles.recordReceived(candidate);
        await NativeOpen.markFromInternet(candidate);
        return candidate;
      } on FileSystemException catch (renameError) {
        // rename 실패: 이번에 만든 자리만 지우고 바로 던짐 (.part는 호출부가 정리)
        try {
          if (placeholder.existsSync() && placeholder.lengthSync() == 0) {
            await placeholder.delete();
          }
        } on FileSystemException catch (cleanupError) {
          throw TransferCleanupException(
            failures: [cleanupError],
            original: renameError,
          );
        }
        rethrow;
      }
    }
  }

  // RAM 바이트를 고른 폴더에 저장 (음성 수동 저장). 받기와 같은 예약 → 쓰기 → 커밋이고 커밋 못 한 .part는 finally가 지움.
  // isStillWanted는 await마다 다시 물음 (그사이 소각돼 바이트가 지워졌으면 0 바이트를 음성인 척 저장하면 안 됨)
  static Future<String?> saveBytes({
    required String directory,
    required String name,
    required List<int> bytes,
    required bool Function() isStillWanted,
  }) async {
    File? partial;
    var committed = false;
    Object? failure;
    try {
      final reserved = await reserveDestination(
        directory: directory,
        name: name,
        // 로컬 저장 하나를 구분하는 이름일 뿐이라 타임스탬프면 충분
        attemptId: 'local-save-${DateTime.now().microsecondsSinceEpoch}',
      );
      partial = reserved.partial;
      if (!isStillWanted()) return null;
      await partial.writeAsBytes(bytes, flush: true);
      if (!isStillWanted()) return null;
      final path = await commitDestination(partial, reserved.finalName);
      committed = true;
      return path;
    } on Object catch (e) {
      failure = e;
      rethrow;
    } finally {
      final leftover = partial;
      if (!committed && leftover != null) {
        try {
          if (leftover.existsSync()) await leftover.delete();
        } on FileSystemException catch (cleanupError) {
          throw TransferCleanupException(
            failures: [cleanupError],
            original: failure,
          );
        }
      }
    }
  }
}

// POSIX EEXIST. osError.errorCode가 플랫폼 그대로의 errno라
// macOS·Linux에선 이 값으로 '그 이름이 이미 있었다'를 구분함
// (Windows는 typeSync 재확인으로 충분)
const int _kFileExistsErrno = 17;

// 최종 이름이 계속 충돌할 때 commitDestination이 시도할 (n) 접미사 개수 상한
const int kMaxCommitAttempts = 100;

// reserveDestination이 피어가 보낸 attemptId에서 남기는 최대 UTF-8 바이트 (나머지는 로컬 난수 접미사가 채움)
const int kMaxAttemptSuffixBytes = 40;

// 폴더·파일 대화상자를 못 띄움 (Linux는 xdg-desktop-portal만 써서 포털 백엔드가 없으면 여기로 옴)
// 화면 쪽이 잡아서 원인을 알려 줌 (안 잡으면 수락을 눌러도 아무 일 없이 사라짐)
class PickerUnavailableException implements Exception {
  const PickerUnavailableException(this.cause);

  final Object cause;

  @override
  String toString() => 'PickerUnavailableException: $cause';
}
