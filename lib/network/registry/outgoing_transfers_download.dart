part of 'outgoing_transfers.dart';

class OutgoingDownload {
  const OutgoingDownload({
    required this.body,
    required this.wireBytes,
    required this.name,
  });

  // wire로 나갈 바이트 (암호화면 이미 봉인됨). 끝까지 흘러야 EOF, 중간에 끊기면 실패
  final Stream<List<int>> body;

  // Content-Length (암호화면 encryptedFileLength)
  final int wireBytes;
  final String name;
}

// push·pull이 같이 쓰는 wire 봉인과 GET 인가, EOF·ACK 합치기
extension OutgoingTransfersDownload on OutgoingTransfers {
  // 보낼 때 평문 스트림을 봉인함. 암호화 전송인데 세션이 없으면 평문으로 안 새고 던짐
  Stream<List<int>> _openWireStream({
    required OutgoingFileSource source,
    required String transferId,
    required String attemptId,
    required PeerLink? link,
    _OutgoingRecipient? recipient,
  }) {
    if (!source.encrypted) return source.openStream();
    if (link == null || !link.canSealFileChunks) {
      throw SecurityException(
        'transfer $transferId is marked encrypted but no crypto session '
        'is available to seal it for the wire',
      );
    }
    return encryptChunks(
      _plainFor(transferId, source, recipient, attemptId),
      link.sealFileChunk,
      transferId: transferId,
      attemptId: attemptId,
      totalBytes: source.size,
    );
  }

  int _wireBytesOf(OutgoingFileSource source) =>
      source.encrypted ? encryptedFileLength(source.size) : source.size;

  // GET /api/download/<id> 인가와 봉인. source가 없으면 null(404), 토큰·attempt·크기·상태가 어긋나면 SecurityException(403).
  // 다 확인한 뒤에만 그 수신자 토큰을 씀 (한 번 쓴 토큰은 끝)
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

    // 검증이 다 끝났으니 여기서 슬롯을 씀 (첫 await 전에)
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
        recipient: recipient,
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
      // 한 바이트도 안 나갔으니 슬롯을 돌려줌: 게이트 타임아웃 같은 내 쪽 사정으로 수신자의 하나뿐인 토큰이 타면 안 됨
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

  // 이 attempt의 바이트가 다 나감 (push는 POST 200, pull은 body EOF). 받는 쪽 커밋까지 끝난 건 아니라서
  // ACK가 이미 왔으면 완료, 아니면 기다림 (타이머는 이 수신자·attempt 것)
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

  // EOF와 ACK가 둘 다 모인 때라 영수증의 내용 해시도 내가 다 내보낸 바이트와 맞춰 볼 수 있음
  void _completeRecipient(String transferId, _OutgoingRecipient recipient) {
    recipient.ackTimer?.cancel();
    recipient
      ..ackTimer = null
      ..phase = _RecipientPhase.complete;
    final source = _outgoing[transferId];
    if (source != null) {
      unawaited(_checkReceipt(transferId, source, recipient));
    }
    _syncTransfer(transferId);
  }
}
