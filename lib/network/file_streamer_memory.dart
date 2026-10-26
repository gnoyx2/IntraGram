part of 'file_streamer.dart';

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
    // 받은 조각은 결과로 옮긴 뒤 덮어씀: 중간 조각 버퍼를 정리해 음성 사본이 중복으로 RAM에 남지 않게 함
    final pieces = <List<int>>[];
    var received = 0;
    try {
      try {
        await for (final chunk in source) {
          if (cancelToken?.isCancelled ?? false) {
            throw const TransferCancelledException();
          }
          pieces.add(chunk);
          received += chunk.length;
          if (received > declaredSize) {
            throw SecurityException(
              'peer sent more than the ${declaredSize}B it declared',
            );
          }
        }
      } on Object {
        // 취소는 소켓을 닫아서 스트림 오류로 보임: 네트워크 실패와 구분되게 취소로 바꿔 던짐
        if (cancelToken?.isCancelled ?? false) {
          throw const TransferCancelledException();
        }
        rethrow;
      }
      if (received != declaredSize) {
        throw SecurityException(
          'peer sent ${received}B but declared exactly ${declaredSize}B '
          '(short EOF)',
        );
      }
      final bytes = Uint8List(received);
      var offset = 0;
      for (final piece in pieces) {
        bytes.setRange(offset, offset += piece.length, piece);
      }
      if (sha256 != null &&
          base64.encode(const DartSha256().hashSync(bytes).bytes) != sha256) {
        SecureBytes.wipe(bytes);
        throw const ContentMismatchException();
      }
      return bytes;
    } finally {
      pieces.forEach(SecureBytes.wipe);
    }
  } finally {
    unregisterCancel?.call();
    client.close(force: true);
  }
}
