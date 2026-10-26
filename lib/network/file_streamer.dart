import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/secure_bytes.dart' show SecureBytes;
import 'package:intragram/network/file_chunks.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/transfer_rate_meter.dart';

export 'package:intragram/network/transfer_rate_meter.dart';

part 'file_streamer_outbound.dart';
part 'file_streamer_memory.dart';
part 'file_streamer_receive.dart';

// 전송 취소 토큰. 청크마다 보고 다음 청크에서 TransferCancelledException을 던져서 정리는 다른 오류와 같은 길로 감 (cancelled 상태는 레지스트리 몫)
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

  // cancel 즉시 부를 콜백 (소켓 닫기·게이트 대기 풀기처럼 다음 청크를 못 기다리는 정리용). 이미 취소됐으면 바로 부름.
  // 돌려주는 해제 함수는 finally에서 꼭 부를 것 (안 그러면 끝난 작업 리스너가 쌓임)
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

// .part를 치우다 정리 자체가 실패함 (close 실패, 삭제 권한 거부 등). 원래 오류와 같이 올려서 다음 정리가 다시 하고 드러나게 함 (경로는 안 담음)
class TransferCleanupException implements Exception {
  const TransferCleanupException({required this.failures, this.original});
  final List<Object> failures;
  final Object? original;
  @override
  String toString() =>
      'TransferCleanupException(${failures.length} cleanup failure(s))';
}

// 예외를 안전한 사유 몇 개로 분류: 원문(피어 IP·포트·OS 코드)이 전송 기록과 화면에 안 새게. 번역은 UI가 그릴 때 함
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

// 파일은 WebSocket으로 안 가고 통째로 버퍼에 담지도 않음: 보내는 쪽은 스트림을 요청 바디로 밀고
// 받는 쪽은 2 MiB씩 바로 디스크에 써서 수 GB도 몇 MiB RAM으로 끝남
final class FileStreamer {
  const FileStreamer._();

  // 테스트 seam: close가 실패하는 handle을 끼워 abort가 그래도 지우는지 봄
  @visibleForTesting
  static Future<RandomAccessFile> Function(File file) debugOpenPartial =
      _openPartial;

  // host는 리터럴 사설 IP여야 함 (마지막으로 한 번 더 검사). 200이 아니면 던짐
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

  // GET으로 당겨서 receive로 씀. host는 리터럴 사설 IP여야 하고 200이 아니면 던짐. decrypt가 있으면 먼저 풂 (declaredSize는 평문 기준)
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
    void Function(String sha256)? onDigest,
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
    onDigest: onDigest,
  );

  // download와 같은 검사로 RAM에만 당김 (음성용). 통째로 들어와서 maxBytes를 넘게 선언하면 소켓을 열기 전에 거절하고 짧은 EOF도 거절
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

  // 쓴 바이트 수를 돌려줌 (구현은 _receive). onDigest가 있으면 쓴(복호화한) 바이트의 SHA-256을 다 쓴 뒤 한 번 알림:
  // offer에 해시가 없는 1:1 전송의 수신 영수증 커밋먼트로 씀 (다시 읽지 않음)
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
    void Function(String sha256)? onDigest,
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
    onDigest: onDigest,
  );
}
