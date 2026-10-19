import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/file_chunks.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/transfer_rate_meter.dart';

export 'package:intragram/network/transfer_rate_meter.dart';

part 'file_streamer_outbound.dart';
part 'file_streamer_receive.dart';

// 진행 중인 전송을 무르는 취소 토큰. 청크마다 확인해서 cancel이 불리면
// 다음 청크에서 TransferCancelledException을 던지고,
// 기존 abort/정리 경로(부분 파일 삭제 등)가 다른 에러와 똑같이 처리함.
// state를 cancelled로 세팅하는 건 호출부(레지스트리) 몫
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final fired = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in fired) {
      listener();
    }
  }

  // callback을 등록해서 cancel이 불리는 즉시 실행 (소켓 닫기,
  // 게이트 대기 해제처럼 다음 청크를 기다리지 않고 당장 정리할 부수효과용)
  // 멱등: 이미 취소된 뒤에 등록하면 바로 한 번 부름. 리턴값은 등록 해제 함수라 정상 완료 경로의 finally에서
  // 반드시 불러서 끝난 작업의 리스너가 쌓이지 않게 함
  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }
}

class TransferCancelledException implements Exception {
  const TransferCancelledException();
  @override
  String toString() => 'TransferCancelledException: transfer was cancelled';
}

// 받은 바이트가 offer(인증된 링크)가 실어 온 SHA-256과 다름: 평문 구간(방 직접 전송)에서 바뀜
class ContentMismatchException implements Exception {
  const ContentMismatchException();
  @override
  String toString() =>
      'ContentMismatchException: received bytes do not match the offer';
}

// 전송이 실패/취소돼 .part를 치우는데 그 정리 자체가 실패함 (파일 handle close 실패, 삭제 권한 거부 등)
// 정리 실패를 삼키지 않고 원래 오류(original)와 정리 오류(failures)를 함께 전달해서, 호출부가 남은 파일을
// 다음 정리에서 재시도하고 사용자/로그에 드러내게 함. 경로는 안 담음
class TransferCleanupException implements Exception {
  const TransferCleanupException({required this.failures, this.original});
  final List<Object> failures;
  final Object? original;
  @override
  String toString() =>
      'TransferCleanupException(${failures.length} cleanup failure(s))';
}

// 잡힌 예외를 몇 안 되는 안전한 사유로 분류: 원본 예외 문자열(피어 IP, 포트, OS 에러 코드)을 전송 기록의 error 필드에 담아
// 화면에 흘리지 않으려는 것. UI가 렌더 시점에 번역함 (SystemEvent와 같은 패턴)
String classifyTransferError(Object error) => switch (error) {
  TransferCleanupException(:final original) =>
    original == null ? 'unknown' : classifyTransferError(original),
  TransferCancelledException() => 'cancelled',
  ContentMismatchException() => 'tampered',
  SecurityException() => 'rejected',
  SocketException() || HttpException() || TlsException() => 'network',
  TimeoutException() => 'network',
  FileSystemException(:final osError)
      when _diskFullCodes.contains(osError?.errorCode) =>
    'diskFull',
  _ => 'unknown',
};

// ENOSPC(POSIX 28), Windows ERROR_DISK_FULL(112)·ERROR_HANDLE_DISK_FULL(39)
const Set<int> _diskFullCodes = {28, 112, 39};

// 파일은 WebSocket으로 안 가고 통째로 버퍼링도 안 됨: 보내는 쪽은 Stream을 요청 바디로 바로 밀고,
// 받는 쪽은 2 MiB 청크가 도착하는 대로 디스크에 써서 수 GB 전송도 양쪽 몇 MiB RAM만 씀
final class FileStreamer {
  const FileStreamer._();

  // 테스트 seam: 받는 쪽이 .part를 쓰려고 여는 파일 handle. close가
  // 실패하는 handle을 끼워 abort가 그래도 파일을 지우는지 검증
  @visibleForTesting
  static Future<RandomAccessFile> Function(File file) debugOpenPartial =
      _openPartial;

  // host는 리터럴 link-local IP여야 함 (여기서 마지막 방어선으로 한 번 더 검사). 200이 아니면 던짐
  static Future<void> send({
    required String host,
    required int port,
    required String transferId,
    required String attemptId,
    required String authToken,
    required String fileName,
    required int totalBytes,
    required int wireBytes,
    required Stream<List<int>> bytes,
    TransferProgress? onProgress,
    CancelToken? cancelToken,
  }) => _send(
    host: host,
    port: port,
    transferId: transferId,
    attemptId: attemptId,
    authToken: authToken,
    fileName: fileName,
    totalBytes: totalBytes,
    wireBytes: wireBytes,
    bytes: bytes,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  // 그룹 방 멤버끼리 직접 전송. host는 리터럴 사설 IP여야 함 (마지막 방어선으로 한 번 더 검사). 200이 아니면 던짐
  // decrypt가 있으면(1:1 암호화 전송) receive에 넘기기 전에
  // 복호화 (declaredSize는 평문 크기 기준이라 강제 로직은 그대로)
  static Future<int> download({
    required String host,
    required int port,
    required String transferId,
    required String attemptId,
    required String authToken,
    required String destinationPath,
    required int declaredSize,
    TransferProgress? onProgress,
    OpenChunk? decrypt,
    CancelToken? cancelToken,
    String? sha256,
  }) => _download(
    host: host,
    port: port,
    transferId: transferId,
    attemptId: attemptId,
    authToken: authToken,
    destinationPath: destinationPath,
    declaredSize: declaredSize,
    onProgress: onProgress,
    decrypt: decrypt,
    cancelToken: cancelToken,
    sha256: sha256,
  );

  // download와 같은 가드 체인이되 바이트를 RAM으로만 당김 (음성 메시지 수신용, 디스크/보관소에 안 감)
  // RAM으로 통째 들어오므로 공개 진입점에서 상한을 강제: declaredSize가 maxBytes(기본
  // kMaxVoiceNoteBytes)를 넘으면 소켓을 열기 전에 SecurityException,
  // 선언한 크기를 못 채운 짧은 EOF도 거부. decrypt가 있으면 크기 강제보다 먼저 복호화
  static Future<Uint8List> downloadToMemory({
    required String host,
    required int port,
    required String transferId,
    required String attemptId,
    required String authToken,
    required int declaredSize,
    OpenChunk? decrypt,
    CancelToken? cancelToken,
    int maxBytes = kMaxVoiceNoteBytes,
    String? sha256,
  }) => _downloadToMemory(
    host: host,
    port: port,
    transferId: transferId,
    attemptId: attemptId,
    authToken: authToken,
    declaredSize: declaredSize,
    decrypt: decrypt,
    cancelToken: cancelToken,
    maxBytes: maxBytes,
    sha256: sha256,
  );

  // 쓴 바이트 수를 리턴. 자세한 설명/구현은 _receive (file_streamer_receive.dart) 참고
  static Future<int> receive({
    required Stream<List<int>> body,
    required String transferId,
    required String attemptId,
    required String destinationPath,
    required int declaredSize,
    TransferProgress? onProgress,
    OpenChunk? decrypt,
    CancelToken? cancelToken,
    String? sha256,
  }) => _receive(
    body: body,
    transferId: transferId,
    attemptId: attemptId,
    destinationPath: destinationPath,
    declaredSize: declaredSize,
    onProgress: onProgress,
    decrypt: decrypt,
    cancelToken: cancelToken,
    sha256: sha256,
  );
}
