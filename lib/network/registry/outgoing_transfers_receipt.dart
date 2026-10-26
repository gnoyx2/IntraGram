part of 'outgoing_transfers.dart';

// 보내는 쪽 수신 영수증: ACK에 실려 온 서명을 지금 attempt의 그 수신자 것으로 붙여 두고, EOF와 ACK가 다 모여
// 완료될 때(_completeRecipient) 확인해 증적에 남김. 영수증이 없거나 틀려도 전송 완료는 예전처럼 ACK로만 정함
extension OutgoingTransfersReceipt on OutgoingTransfers {
  void handleDeliveryReceipt(
    String transferId, {
    required String attemptId,
    required String actorKey,
    required Map<String, dynamic> receipt,
  }) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null ||
        recipient.attemptId != attemptId ||
        recipient.isTerminal) {
      return;
    }
    recipient.receipt = SignedAttestation.fromWire(receipt);
  }

  // 서명이 맞고, 서명 키가 그 수신자 peerId의 키이고, 이 전송·attempt·보낸 사람(나)·내가 내보낸 내용 해시를 가리켜야 verified.
  // 하나라도 틀리면 rejected로 남김 (받은 바이트가 달랐거나 다른 시도 영수증을 재생한 것)
  Future<void> _checkReceipt(
    String transferId,
    OutgoingFileSource source,
    _OutgoingRecipient recipient,
  ) async {
    final generation = store.evidence.generation;
    final receipt = recipient.receipt;
    if (receipt == null) return;
    recipient.receipt = null;
    final expected = source.spec.digest ?? recipient.sentDigest;
    final bound =
        receipt.kind == AttestationKind.deliveryCommitted &&
        receipt.outcome == 'committed' &&
        receipt.policy ==
            (source.spec.voice
                ? 'delivery/voice-ram'
                : 'delivery/file-commit') &&
        receipt.subjectId == transferId &&
        receipt.attemptId == recipient.attemptId &&
        receipt.counterpartId == identity.peerId &&
        receipt.counterpartKey != null &&
        identity.publicKey != null &&
        base64.encode(receipt.counterpartKey!) ==
            base64.encode(identity.publicKey!) &&
        receipt.signerPeerId == recipient.key &&
        expected != null &&
        receipt.commitment == expected;
    final verified = bound && await receipt.verify();
    store.evidence.record(
      receipt,
      verified: verified,
      sinceGeneration: generation,
      conversationId: source.conversationId,
      transferId: transferId,
    );
  }

  // 방은 offer 전에 잰 SHA-256이 있어서 그대로 쓰고, 1:1은 내보내는 길에 같은 해시를 잼 (offer 전에 파일을 한 번 더 읽지 않음)
  Stream<List<int>> _plainFor(
    String transferId,
    OutgoingFileSource source,
    _OutgoingRecipient? recipient,
    String attemptId,
  ) {
    final plain = source.openStream();
    if (recipient == null || source.spec.digest != null) return plain;
    return sha256Tap(plain, (digest) {
      if (recipient.attemptId != attemptId) return;
      recipient.sentDigest = digest;
      store.updateTransfer(
        transferId,
        (t) => t.copyWith(contentCommitment: digest),
      );
    });
  }
}
