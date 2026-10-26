part of '../evidence_store.dart';

// 오프라인 앵커 교환 쪽 (audit_bundle_exchange.dart): 내 배치에 증인 영수증을 붙이고, 남의 배치를 증인으로 기록함
extension EvidenceAnchors on EvidenceStore {
  // 증인 앵커를 붙임: 증인 서명이 맞고, 내 배치 머리를 가리키고, 그 링크 상대가 서명했어야 함
  Future<bool> attachAnchor(
    AnchorReceipt receipt, {
    required String witnessPeerId,
  }) async {
    final generation = _generation;
    final target = batch(receipt.batchNo);
    if (_frozen ||
        target == null ||
        receipt.witnessPeerId != witnessPeerId ||
        bytesEqual(receipt.witnessKey, receipt.requesterKey) ||
        !receipt.binds(target.header) ||
        !await receipt.verify()) {
      return false;
    }
    if (!identical(batch(receipt.batchNo), target) ||
        _disposed ||
        _frozen ||
        generation != _generation) {
      return false;
    }
    _batches[receipt.batchNo] = target.withAnchor(receipt);
    _notify();
    return true;
  }

  // 남의 배치를 증인으로 기록. 같은 기기·번호에 다른 루트면 상충으로 남기고 true를 돌려줌
  bool witness(String peerId, BatchHeader header) {
    if (_disposed || _frozen) return false;
    final root = base64.encode(header.root);
    final conflict = _witnessed.any(
      (w) => w.peerId == peerId && w.batchNo == header.no && w.root != root,
    );
    _witnessed.add(
      WitnessRecord(
        peerId: peerId,
        batchNo: header.no,
        root: root,
        witnessedAtMs: DateTime.now().millisecondsSinceEpoch,
        conflict: conflict,
      ),
    );
    if (_witnessed.length > EvidenceStore.maxWitnessed) {
      _witnessed.removeAt(0);
    }
    _notify();
    return conflict;
  }
}
