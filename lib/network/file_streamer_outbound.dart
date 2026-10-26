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
    // HttpClient는 3xx를 기본으로 따라가서 딴 호스트로 튈 수 있음: 끄고 3xx는 아래에서 실패로 봄
    request.followRedirects = false;
    request.headers
      ..set('x-transfer-id', transferId)
      ..set('x-transfer-attempt', attemptId)
      ..set('x-transfer-token', authToken)
      ..set('x-file-name', base64.encode(utf8.encode(fileName)))
      ..set('x-file-size', '$totalBytes');
    request.headers.contentType = ContentType.binary;
    // Content-Length는 wire 바이트 (암호화면 평문보다 큼). 평문 크기를 넣으면 dart:io가 중간에 끊음
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
  void Function(String sha256)? onDigest,
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
    // 연결은 connectionTimeout이 보지만 붙고 나서 응답 헤더를 안 주는 피어는 따로 stall timeout으로 끊음
    final response = await request.close().timeout(kTransferStallTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'origin refused download (HTTP ${response.statusCode})',
      );
    }
    // receive가 끝나길 여기서 기다려야 finally의 close가 바디를 받는 중에 안 끊음
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
      onDigest: onDigest,
    );
  } finally {
    unregisterCancel?.call();
    client.close(force: true);
  }
}
