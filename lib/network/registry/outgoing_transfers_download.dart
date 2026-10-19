part of 'outgoing_transfers.dart';

class OutgoingDownload {
  const OutgoingDownload({
    required this.body,
    required this.wireBytes,
    required this.name,
  });

  // 실제 wire에 나갈 바이트 스트림 (암호화면 이미 AEAD로 감싸진
  // 상태). 끝까지 흘러야만 그 attempt의 wire EOF로 기록되고,
  // 응답 구독이 중간에 취소되면 실패로 기록됨
  final Stream<List<int>> body;

  // Content-Length로 선언할 정확한 값: 평문이면 OutgoingFileSource.size,
  // 암호화면 encryptedFileLength
  final int wireBytes;
  final String name;
}

// openDownload/push 전송 둘 다 쓰는 wire wrapping과,
// GET 인가/wire EOF/file_received ACK 결합 규칙
extension OutgoingTransfersDownload on OutgoingTransfers {
  // source의 평문 스트림을 실제 전송 시점에 감쌈 (push와 pull
  // 둘 다 이 함수 하나만 씀). encrypted가 아니면 평문 그대로
  // encrypted인데 link가 없거나 세션이 안 됐으면 평문 폴백 없이 던져서 호출부가 실패로 처리
  Stream<List<int>> _openWireStream({
    required OutgoingFileSource source,
    required String transferId,
    required String attemptId,
    required PeerLink? link,
  }) {
    if (!source.encrypted) return source.openStream();
    if (link == null || !link.canSealFileChunks) {
      throw SecurityException(
        'transfer $transferId is marked encrypted but no crypto session '
        'is available to seal it for the wire',
      );
    }
    return encryptChunks(
      source.openStream(),
      link.sealFileChunk,
      transferId: transferId,
      attemptId: attemptId,
      totalBytes: source.size,
    );
  }

  int _wireBytesOf(OutgoingFileSource source) =>
      source.encrypted ? encryptedFileLength(source.size) : source.size;

  // GET /api/download/<id> 인가와 AEAD wrapping을 한 곳에서 함 (server_routes.dart는
  // 이 결과만 서빙하고 openStream을 직접 안 읽음). staged source가 없으면 null(404),
  // 토큰/attempt/선언 크기/현재 상태가 어긋나면 SecurityException(403)
  // 전부 검증한 뒤에만 그 수신자의 토큰을 소비함 (성공한 토큰 재사용 불가). 평문 폴백 없음
  Future<OutgoingDownload?> openDownload({
    required String transferId,
    required String attemptId,
    required String token,
    required int declaredSize,
  }) async {
    final source = _outgoing[transferId];
    if (source == null) return null;
    if (source.mode != FileTransferMode.pull) {
      throw SecurityException('download not authorized');
    }
    if (declaredSize != source.size) {
      throw SecurityException('download declared size mismatch');
    }
    final recipient = source._recipients.values.firstWhereOrNull(
      (r) => r.pullToken != null && constantTimeEquals(token, r.pullToken!),
    );
    if (recipient == null) throw SecurityException('download not authorized');
    if (recipient.attemptId != attemptId) {
      throw SecurityException('download attempt is stale');
    }
    final previous = recipient.phase;
    if (recipient.tokenConsumed ||
        (previous != _RecipientPhase.offered &&
            previous != _RecipientPhase.accepted)) {
      throw SecurityException('download token already used');
    }

    // 여기서부터 슬롯을 소비함 (검증이 전부 끝난 뒤, 첫 await 전에)
    recipient
      ..tokenConsumed = true
      ..phase = _RecipientPhase.transferring;
    final cancelToken = CancelToken();
    recipient.cancelToken = cancelToken;
    final done = Completer<void>();
    recipient.active = done.future;
    var acquired = false;
    try {
      await gate.acquire(
        timeout: kTransferStallTimeout,
        cancelToken: cancelToken,
      );
      acquired = true;
      if (cancelToken.isCancelled) throw const TransferCancelledException();
      final link =
          _linkForRecipient(source, recipient) ??
          _linkFor(source.conversationId);
      final wire = _openWireStream(
        source: source,
        transferId: transferId,
        attemptId: attemptId,
        link: link,
      );
      _syncTransfer(transferId);
      return OutgoingDownload(
        body: _pullBody(
          transferId: transferId,
          source: source,
          recipient: recipient,
          attemptId: attemptId,
          wire: wire,
          cancelToken: cancelToken,
          done: done,
        ),
        wireBytes: _wireBytesOf(source),
        name: source.name,
      );
    } on Object {
      // 응답 바이트가 한 바이트도 안 나갔으니 슬롯을 그대로 돌려줌:
      // 게이트 대기 타임아웃이나 "암호화 세션 없음" 같은 서버 쪽
      // 사유로
      // 수신자의 유일한 토큰이 타버리면 안 됨
      if (acquired) gate.release();
      if (recipient.attemptId == attemptId &&
          identical(_outgoing[transferId], source) &&
          identical(recipient.cancelToken, cancelToken) &&
          !cancelToken.isCancelled &&
          recipient.phase == _RecipientPhase.transferring) {
        recipient
          ..tokenConsumed = false
          ..phase = previous
          ..cancelToken = null
          ..active = null;
      }
      done.complete();
      _syncTransfer(transferId);
      rethrow;
    }
  }

  // 이 attempt의 데이터 경로가 끝까지 감 (push: POST 200, pull: body EOF). EOF는
  // 바이트가 다 나갔다는 뜻일 뿐 받는 쪽의 검증/커밋 완료가 아니라서, 같은 attempt의 유효한 file_received
  // ACK가 이미 왔으면 complete, 아직이면 ACK를 기다림 (타이머는 이 수신자/attempt에 귀속)
  void _onWireEof(
    String transferId,
    OutgoingFileSource source,
    _OutgoingRecipient recipient,
  ) {
    if (recipient.isTerminal || recipient.wireEof) return;
    recipient.wireEof = true;
    if (recipient.ackReceived) {
      _completeRecipient(transferId, recipient);
      return;
    }
    recipient.phase = _RecipientPhase.awaitingAck;
    final attempt = recipient.attemptId;
    recipient.ackTimer?.cancel();
    recipient.ackTimer = Timer(ackTimeout, () {
      if (recipient.attemptId != attempt ||
          recipient.phase != _RecipientPhase.awaitingAck) {
        return;
      }
      recipient
        ..ackTimer = null
        ..error = 'network'
        ..phase = _RecipientPhase.failed;
      _syncTransfer(transferId);
    });
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(transferredBytes: source.size, bytesPerSecond: 0),
    );
    _syncTransfer(transferId);
  }

  void _completeRecipient(String transferId, _OutgoingRecipient recipient) {
    recipient.ackTimer?.cancel();
    recipient
      ..ackTimer = null
      ..phase = _RecipientPhase.complete;
    _syncTransfer(transferId);
  }
}
