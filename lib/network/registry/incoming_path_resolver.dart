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

  // 데스크톱은 폴더 선택 창을 띄우고, 모바일은 기존 앱 문서 디렉터리 내 IntraGram/을 사용함. 음성 수동 저장 기능에서도 호출함
  static Future<String?> defaultChooseDirectory(String suggestedName) async {
    final mobileDir = await mobileSaveDir();
    if (mobileDir != null) return mobileDir;
    // 창 제목은 로케일에 의존하지 않는 파일 이름만 사용함 (네트워크 계층에는 번역 문자열이 없음)
    final String? picked;
    try {
      picked = await FilePicker.getDirectoryPath(dialogTitle: suggestedName);
    } on Exception catch (error) {
      throw PickerUnavailableException(error);
    }
    if (picked != null) await IncomingSessionFiles.rememberDirectory(picked);
    return picked;
  }

  // 기존에 받은 파일의 위치를 유지함. 모바일 고정 저장 폴더 (데스크톱은 null)
  static Future<String?> mobileSaveDir() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return null;
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'IntraGram');
  }

  // 이번 시도 전용 .part 파일을 배타적 생성(exclusive create)으로 예약함. 동일한 이름을 동시에 수신하는 다른 시도와 섞이지 않도록 attempt를 포함하고,
  // 최종 파일명은 commitDestination에서 결정함. 디렉터리는 심링크를 해소한 실제 경로 기준이며 파일명이 상위 경로를 벗어나지 않는지 사전에 검증함.
  // attemptId는 피어가 보낸 값이므로 영숫자·하이픈·언더스코어만 남기고 로컬 난수를 덧붙임
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

  // 완료된 .part 파일을 finalName으로 커밋함 (성공한 전송에만 적용). 최종 파일명을 배타적 생성으로 선점하고 중복되면 (n) 접미사를 붙여 재시도한 뒤,
  // 선점한 위치로 rename함 (기존 파일 위 rename은 원자적으로 대체됨). 실제 파일명 충돌만 다음 번호로 재시도하고 기타 I/O 오류는 즉시 던짐
  // (권한 오류나 디스크 용량 부족 시 불필요한 재시도를 방지함). rename 실패 시 이번에 생성한 빈 자리만 정리함 (사용자 기존 파일은 보존함)
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

  // 메모리 상의 바이트를 선택된 폴더에 저장함 (음성 수동 저장). 수신과 동일하게 예약 → 쓰기 → 커밋 단계를 거치며 미커밋 .part 파일은 finally에서 삭제함.
  // isStillWanted는 await 지점마다 호출됨 (그사이 데이터 소각이 발생했을 때 빈 파일을 정상 음성으로 저장하지 않도록 방지함)
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
        // 단일 로컬 저장을 식별하기 위한 값이므로 타임스탬프로 지정함
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

// POSIX EEXIST. osError.errorCode가 플랫폼 네이티브 errno이므로
// macOS·Linux에서는 이 값으로 기존 파일명 중복을 식별함
// (Windows는 typeSync 재확인으로 처리함)
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
