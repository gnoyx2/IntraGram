import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

// 수락된 인커밍 파일의 디스크 목적지를 정함: 목적지 폴더 고르기(+세션 캐싱)와 이름 충돌 시 유니크화만 담당
// 실제 traversal 방어(basename 정제 + isWithin 증명)는 core/path_safety.dart에
// 있고 IncomingTransfers.accept가 직접 호출함
class IncomingPathResolver {
  IncomingPathResolver({this.chooseDirectory});

  // 수락된 파일이 어디 써질지 고르는 seam. 프로덕션에선
  // null(_defaultChooseDirectory의 플랫폼 로직), 테스트는 임시 디렉토리 주입
  final Future<String?> Function(String suggestedName)? chooseDirectory;

  String? _sessionSaveDir;

  // 테스트 seam이 이기고, 아니면 유저가 처음 고른 폴더를 세션 동안
  // 기억함 (RAM 전용). 반복 수락/검증된 피어 자동 수락이 다시 안
  // 물어봄
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

  // 프로덕션 목적지 피커: 데스크톱은 폴더 다이얼로그, 모바일은 앱 문서 디렉토리 밑 IntraGram/
  // public인 이유: RAM 전용 음성 메시지를 수동 저장하는 버튼(voice_player.dart)도 같은 로직을 씀
  static Future<String?> defaultChooseDirectory(String suggestedName) async {
    final mobileDir = await mobileSaveDir();
    if (mobileDir != null) return mobileDir;
    // 창 제목은 언어와 무관한 파일 이름만 (네트워크 계층엔 번역 테이블이 없음)
    final String? picked;
    try {
      picked = await FilePicker.getDirectoryPath(dialogTitle: suggestedName);
    } on Exception catch (error) {
      throw PickerUnavailableException(error);
    }
    if (picked != null) await IncomingSessionFiles.rememberDirectory(picked);
    return picked;
  }

  // 모바일 고정 저장 폴더 (데스크톱은 null: 매 세션 사용자가 고름)
  static Future<String?> mobileSaveDir() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return null;
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'IntraGram');
  }

  // directory 안에 이번 시도(attemptId) 전용 임시 파셜을 exclusive create로 예약 (파일
  // 선택이 승인되기 전엔 아무것도 안 만듦). 같은 이름을 동시에 수락한 다른 시도와 안 섞이게 attemptId로
  // 유니크한 .intragram-<attempt>.part에 쓰고 최종 이름은 commitDestination이 확정
  // directory는 resolveSymbolicLinks로 canonical 경로를 구해 그 위에서만 작업 (심링크가 가리키는 승인
  // 폴더 자체가 기준). name은 safeBasename +
  // resolveWithin으로 directory 밖으로 못 나가는 걸 미리 증명
  // attemptId는 상대가 보낸 신뢰 안 하는 문자열이라 영숫자/-/_만 남기고 kMaxAttemptSuffixBytes로
  // 자른 뒤 로컬 난수 접미사를 붙여 앱 소유 이름으로 만듦 (동시 재시도끼리도 안 겹침)
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

  // 끝난 partial을 finalName으로 커밋 (성공한 전송에서만 불림). 최종 이름을 exclusive
  // create로 먼저 예약해서(이미 있으면 파일/디렉토리/심링크/깨진 링크 모두 실패) 충돌하면 (n) 접미사로
  // 재시도하고, 그 placeholder에 partial을 rename (대상이 파일이면 원자적으로 덮어씀)
  // create와 rename을 별도 try/catch로 다룸: 아무 FileSystemException이나
  // "이름 충돌"로 보면 권한 거부/디스크 꽉 참 같은 오류가 이름만 바꾸며 kMaxCommitAttempts(100)번
  // 재시도됨. 실제 이름 충돌만 다음 이름으로 넘어가고 그 외는 즉시 던짐
  // rename 실패는 이번 호출이 만든 placeholder만 지우고 던짐 (사용자 파일은 절대 안 지움:
  // 예약이 exclusive create라 원래 있던 파일은 placeholder가 될 수 없고, 지울
  // 때도 빈 파일일 때만). 못 지우면 rename 오류와 함께 TransferCleanupException
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
        // 그 이름이 실제로 이미 존재할 때만(우리가 방금 만들려던 그 경로) 충돌로 보고 다음 이름을 시도
        // 그 외(권한 거부, 디스크 꽉 참, 상위 디렉터리 소실 등)는 이름을 바꿔도 안 풀리므로 즉시 던짐
        final isNameCollision =
            placeholder.existsSync() ||
            e.osError?.errorCode == _kFileExistsErrno;
        if (!isNameCollision) rethrow;
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
        // rename 실패: 이번 호출이 만든 placeholder만 지우고(partial은
        // 호출부 finally가 소유 파셜 정리를 맡음) 다음 이름으로 안 돌고 바로
        // 던짐
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

  // RAM 바이트를 사용자가 고른 directory에 저장 (음성 메시지 수동 저장): 일반 수신과 같은 reserve
  // -> write -> commit 계약이고 커밋 못 한 파셜은 어떤 실패/중단에서도 finally가 지움
  // isStillWanted는 await 뒤마다 다시 물음 (그 사이 화면이 닫히거나 소각돼
  // bytes가 지워졌을 수 있고 0 바이트를 "저장된 음성"으로 쓰면 안 됨). false면
  // 커밋 안 하고 null. 파셜 삭제 자체가 실패하면 TransferCleanupException
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
        // wire attempt가 아니라 로컬 저장 하나를 식별하는
        // 이름일 뿐이라 attemptId 신뢰 경계가 없음: 타임스탬프면
        // 충분
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
// macOS/Linux에선 이 값으로 "그 이름이 이미 있었다"를 구분함
// (Windows는 existsSync() 재확인으로 충분)
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
