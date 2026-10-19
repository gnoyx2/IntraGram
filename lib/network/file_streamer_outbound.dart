part of 'file_streamer.dart';

Future<void> _send({
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
}) async {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    throw SecurityException('file transfer host "$host" is not a literal IP');
  }
  NetworkGuard.assertReachable(address);

  final client = NetworkGuard.createPeerHttpClient();
  final unregisterCancel = cancelToken?.onCancel(
    () => client.close(force: true),
  );
  try {
    final request = await client.openUrl(
      'POST',
      Uri(scheme: 'http', host: host, port: port, path: '/api/transfer'),
    );
    // 3xx는 다른 호스트로 튈 수 있는데 Dart HttpClient는 기본으로 따라감. 파일 전송은 이 정확한 피어와만 하는 거라
    // 리다이렉트를 끄고, 3xx 응답은 아래 statusCode 검사가 에러로 처리함
    request.followRedirects = false;
    request.headers
      ..set('x-transfer-id', transferId)
      ..set('x-transfer-attempt', attemptId)
      ..set('x-transfer-token', authToken)
      ..set('x-file-name', base64.encode(utf8.encode(fileName)))
      ..set('x-file-size', '$totalBytes');
    request.headers.contentType = ContentType.binary;
    // wireBytes는 실제로 wire에 쓸 바이트 수 (암호화면 encryptedFileLength로
    // 미리 계산). x-file-size용 평문 크기 totalBytes와 섞으면 안 됨
    // 예전엔 Content-Length를 totalBytes로 잘못 박아 "Content
    // size exceeds specified contentLength"로 끊겼음
    request.contentLength = wireBytes;

    final meter = RateMeter();
    await request.addStream(
      fixedSizeChunks(bytes, kFileChunkBytes)
          .map((chunk) {
            if (cancelToken?.isCancelled ?? false) {
              throw const TransferCancelledException();
            }
            meter.add(chunk.length);
            meter.maybeReport(onProgress);
            return chunk;
          })
          .timeout(kTransferStallTimeout),
    );

    final response = await request.close().timeout(kTransferStallTimeout);
    await response.drain<void>().timeout(kTransferStallTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'peer refused transfer (HTTP ${response.statusCode})',
      );
    }
    onProgress?.call(totalBytes > 0 ? totalBytes : meter.total, 0);
  } finally {
    unregisterCancel?.call();
    client.close(force: true);
  }
}

Future<int> _download({
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
}) async {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    throw SecurityException('download host "$host" is not a literal IP');
  }
  NetworkGuard.assertReachable(address);

  final client = NetworkGuard.createPeerHttpClient();
  final unregisterCancel = cancelToken?.onCancel(
    () => client.close(force: true),
  );
  try {
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/download/$transferId',
      ),
    );
    request.followRedirects = false;
    request.headers
      ..set('x-transfer-token', authToken)
      ..set('x-transfer-attempt', attemptId)
      ..set('x-file-size', '$declaredSize');
    // 연결은 connectionTimeout이 커버하지만 수락 후 응답
    // 헤더가 아예 안 오는 피어는 별개 문제라 stall timeout을
    // 따로 걺
    final response = await request.close().timeout(kTransferStallTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'origin refused download (HTTP ${response.statusCode})',
      );
    }
    // finally의 client.close(force: true)가 응답 바디를 마저 받기 전에 소켓을 끊을 수 있었음:
    // receive()가 끝나길 실제로 기다려야 finally가 그 전에 안 닫음
    return await FileStreamer.receive(
      body: response,
      transferId: transferId,
      attemptId: attemptId,
      destinationPath: destinationPath,
      declaredSize: declaredSize,
      onProgress: onProgress,
      decrypt: decrypt,
      cancelToken: cancelToken,
      sha256: sha256,
    );
  } finally {
    unregisterCancel?.call();
    client.close(force: true);
  }
}

Future<Uint8List> _downloadToMemory({
  required String host,
  required int port,
  required String transferId,
  required String attemptId,
  required String authToken,
  required int declaredSize,
  required int maxBytes,
  OpenChunk? decrypt,
  CancelToken? cancelToken,
  String? sha256,
}) async {
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    throw SecurityException('download host "$host" is not a literal IP');
  }
  NetworkGuard.assertReachable(address);
  if (declaredSize < 0) {
    throw SecurityException(
      'refused transfer: declared size $declaredSize is negative',
    );
  }
  if (declaredSize > maxBytes) {
    throw SecurityException(
      'refused in-memory download: declared size ${declaredSize}B exceeds '
      'the ${maxBytes}B limit',
    );
  }

  final client = NetworkGuard.createPeerHttpClient();
  final unregisterCancel = cancelToken?.onCancel(
    () => client.close(force: true),
  );
  try {
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/download/$transferId',
      ),
    );
    request.followRedirects = false;
    request.headers
      ..set('x-transfer-token', authToken)
      ..set('x-transfer-attempt', attemptId)
      ..set('x-file-size', '$declaredSize');
    final response = await request.close().timeout(kTransferStallTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'origin refused download (HTTP ${response.statusCode})',
      );
    }
    final stallGuarded = response.timeout(kTransferStallTimeout);
    final source = decrypt == null
        ? stallGuarded
        : decryptChunks(
            stallGuarded,
            decrypt,
            transferId: transferId,
            attemptId: attemptId,
            totalBytes: declaredSize,
          );
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in source) {
        if (cancelToken?.isCancelled ?? false) {
          throw const TransferCancelledException();
        }
        if (builder.length + chunk.length > declaredSize) {
          throw SecurityException(
            'peer sent more than the ${declaredSize}B it declared',
          );
        }
        builder.add(chunk);
      }
    } on Object {
      // 취소는 소켓을 강제로 닫아서 응답 스트림 오류로 나타나므로, 호출부가 네트워크 실패와 구분하도록 취소 예외로 통일
      if (cancelToken?.isCancelled ?? false) {
        throw const TransferCancelledException();
      }
      rethrow;
    }
    if (builder.length != declaredSize) {
      throw SecurityException(
        'peer sent ${builder.length}B but declared exactly ${declaredSize}B '
        '(short EOF)',
      );
    }
    final bytes = builder.takeBytes();
    if (sha256 != null &&
        base64.encode(const DartSha256().hashSync(bytes).bytes) != sha256) {
      bytes.fillRange(0, bytes.length, 0);
      throw const ContentMismatchException();
    }
    return bytes;
  } finally {
    unregisterCancel?.call();
    client.close(force: true);
  }
}
