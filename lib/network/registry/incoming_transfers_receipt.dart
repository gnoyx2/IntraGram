part of 'incoming_transfers.dart';

extension _IncomingReceipt on IncomingTransfers {
  // 크기·무결성 검증과 커밋까지 완료된 전송의 수신 영수증: 자체 신원 키로 서명해 로컬 증적에 기록하고 file_received에 첨부함.
  // 앱 링크로 수신된 전송에만 해당함 (브라우저 게스트는 연결할 신원 키가 없음). 커밋먼트 산출 실패나 서명 키 부재 시 null로 처리되어 기본 ACK만 전송됨
  Future<Map<String, dynamic>?> _receiptFor(
    FileTransfer transfer,
    String attemptId,
    String? digest,
    PeerLink? link,
  ) async {
    final sender = transfer.senderPeerId;
    if (_closed ||
        link == null ||
        link.transport != PeerTransport.app ||
        sender == null ||
        digest == null) {
      return null;
    }
    final senderKey = transfer.senderPubKey == null
        ? link.remoteIdentityKey
        : wireBytes(transfer.senderPubKey, length: 32);
    if (senderKey == null ||
        senderKey.length != 32 ||
        isSmallOrderKey(senderKey) ||
        peerIdOfKey(senderKey) != sender) {
      return null;
    }
    final signed = await store.evidence.issue(
      AttestationDraft(
        kind: AttestationKind.deliveryCommitted,
        subjectId: transfer.id,
        attemptId: attemptId,
        counterpartId: sender,
        counterpartKey: senderKey,
        commitment: digest,
        policy: transfer.voice ? 'delivery/voice-ram' : 'delivery/file-commit',
        outcome: 'committed',
      ),
      conversationId: transfer.conversationId,
      transferId: transfer.id,
    );
    return signed?.toWire();
  }

  // 선택적 서명은 추적 중인 I/O 밖에서 진행: 패닉이 영수증 서명·전송을 기다리지 않음.
  void _acknowledge(FileTransfer transfer, String attemptId, String? digest) {
    unawaited(_sendAcknowledgement(transfer, attemptId, digest));
  }

  Future<void> _sendAcknowledgement(
    FileTransfer transfer,
    String attemptId,
    String? digest,
  ) async {
    final generation = store.evidence.generation;
    // 커밋의 await 중 소각·와이프·새 시도가 왔으면 옛 레코드로 증적을 다시 만들지 않음.
    final current = store.transfer(transfer.id);
    if (current == null ||
        current.state != TransferState.complete ||
        (current.attemptId ?? current.id) != attemptId ||
        current.contentCommitment != digest) {
      return;
    }
    final link = _linkForTransfer(current);
    if (_closed || link == null || link.isClosed) return;
    Map<String, dynamic>? receipt;
    try {
      receipt = await _receiptFor(current, attemptId, digest, link);
    } on Object {
      // 선택적 서명을 못 만들어도 기존 ACK는 보냄.
    }
    if (_closed || link.isClosed || generation != store.evidence.generation) {
      return;
    }
    try {
      await link.sendFileReceived(
        transfer.id,
        attemptId: attemptId,
        receipt: receipt,
      );
    } on Object {
      // 링크가 닫히는 동안 ACK 실패는 증적이나 수신 커밋을 되돌리지 않음.
    }
  }
}
