import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'package:intragram/audit/anchor_receipt.dart';
import 'package:intragram/audit/attestation.dart';
import 'package:intragram/audit/batch.dart';
import 'package:intragram/audit/evidence_entry.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/core/app_identity.dart';

export 'package:intragram/audit/anchor_receipt.dart';
export 'package:intragram/audit/attestation.dart';
export 'package:intragram/audit/batch.dart';
export 'package:intragram/audit/evidence_entry.dart';

part 'evidence_store/anchors.dart';

// RAM 전용 증적 집계기: Vault 스냅샷과 안 섞이고 디스크에 안 씀. secureWipe(패닉·재잠금·종료)가 clear해서 같이 사라짐.
// 서명은 비동기라 그사이 clear되면(세대가 바뀌면) 늦게 끝난 서명은 버림. 상한을 넘으면 오래된 것부터 버림
final class EvidenceStore extends ChangeNotifier {
  static const int maxEntries = 512;
  static const int maxBatches = 64;
  static const int maxWitnessed = 64;

  AppIdentity? _signer;
  int _generation = 0;
  bool _disposed = false;
  bool _frozen = false;
  int _nextBatchNo = 1;
  Future<void> _sealing = Future<void>.value();

  final List<EvidenceEntry> _entries = <EvidenceEntry>[];
  final Map<int, MerkleBatch> _batches = <int, MerkleBatch>{};
  final List<WitnessRecord> _witnessed = <WitnessRecord>[];

  // LinkRegistry가 실행별 신원을 묶음. 키 없는 신원(화면 테스트용)이면 아무것도 서명하지 않음
  void bindSigner(AppIdentity identity) => _signer = identity;

  bool get canSign => !_disposed && !_frozen && _signer?.publicKey != null;

  // clear마다 오름. 사건 시점에 잡아 issue에 넘기면 그 뒤 소각(패닉)된 세션에 늦은 증적이 안 붙음
  int get generation => _generation;

  List<EvidenceEntry> get entries => List.unmodifiable(_entries);
  List<MerkleBatch> get batches => List.unmodifiable(_batches.values);
  List<WitnessRecord> get witnessed => List.unmodifiable(_witnessed);

  Iterable<EvidenceEntry> get unbatched => _entries.where(
    (e) => e.batchNo == null && e.status != EvidenceStatus.rejected,
  );

  Iterable<EvidenceEntry> forTransfer(String transferId) =>
      _entries.where((e) => e.transferId == transferId);

  MerkleBatch? batch(int no) => _batches[no];

  Future<SignedAttestation?> issue(
    AttestationDraft draft, {
    String? conversationId,
    String? transferId,
    int? sinceGeneration,
  }) async {
    final signer = _signer;
    final generation = sinceGeneration ?? _generation;
    if (!canSign || signer == null || generation != _generation) return null;
    final SignedAttestation signed;
    try {
      signed = await SignedAttestation.sign(signer, draft);
    } on StateError {
      return null; // 그사이 키가 사라짐
    }
    if (generation != _generation || _disposed) return null;
    _add(
      EvidenceEntry(
        attestation: signed,
        status: EvidenceStatus.issued,
        leafSalt: randomBytes(16),
        conversationId: conversationId,
        transferId: transferId,
      ),
    );
    return signed;
  }

  // 상대가 서명한 증적. 바인딩·서명 확인은 호출부 몫이고 그 결과를 상태로 남김
  void record(
    SignedAttestation attestation, {
    required bool verified,
    String? conversationId,
    String? transferId,
    int? sinceGeneration,
  }) {
    if (_disposed ||
        _frozen ||
        (sinceGeneration != null && sinceGeneration != _generation)) {
      return;
    }
    if (_entries.any((e) => e.attestation.eventId == attestation.eventId)) {
      return;
    }
    _add(
      EvidenceEntry(
        attestation: attestation,
        status: verified ? EvidenceStatus.verified : EvidenceStatus.rejected,
        leafSalt: randomBytes(16),
        conversationId: conversationId,
        transferId: transferId,
      ),
    );
  }

  // 아직 배치에 없는 증적을 한 배치로 봉인하고 루트에 서명함. 동시에 불러도 하나씩 (번호가 안 겹침)
  Future<MerkleBatch?> seal() {
    final generation = _generation;
    final run = _sealing.then(
      (_) => generation == _generation ? _sealOnce() : null,
    );
    _sealing = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<MerkleBatch?> _sealOnce() async {
    final signer = _signer;
    final pending = unbatched.toList();
    if (!canSign || signer == null || pending.isEmpty) return null;
    final generation = _generation;
    final leaves = <Uint8List>[for (final e in pending) e.leaf];
    final BatchHeader header;
    try {
      header = await BatchHeader.sign(signer, no: _nextBatchNo, leaves: leaves);
    } on StateError {
      return null;
    }
    if (generation != _generation || _disposed) return null;
    _nextBatchNo++;
    final batched = <String, int>{
      for (var i = 0; i < pending.length; i++)
        pending[i].attestation.eventId: i,
    };
    for (var i = 0; i < _entries.length; i++) {
      final index = batched[_entries[i].attestation.eventId];
      if (index != null) _entries[i] = _entries[i].inBatch(header.no, index);
    }
    final batch = MerkleBatch(
      header: header,
      leaves: List<Uint8List>.unmodifiable(leaves),
      eventIds: List<String>.unmodifiable(
        pending.map((e) => e.attestation.eventId),
      ),
    );
    _batches[header.no] = batch;
    if (_batches.length > maxBatches) _batches.remove(_batches.keys.first);
    _notify();
    return batch;
  }

  // 증명 경로 (그 배치에 든 증적만)
  List<Uint8List>? proofFor(EvidenceEntry entry) {
    final no = entry.batchNo;
    final index = entry.batchIndex;
    final batch = no == null ? null : this.batch(no);
    if (batch == null || index == null) return null;
    return merkleProof(batch.leaves, index);
  }

  void freeze() {
    _frozen = true;
    clear();
  }

  void resume() => _frozen = false;

  void clear() {
    _generation++;
    // 배치 번호는 안 되돌림: 재잠금은 서명 신원을 그대로 두어서 같은 키·번호로 다른 루트가 나가면 증인이 상충으로 봄
    _entries.clear();
    _batches.clear();
    _witnessed.clear();
    _notify();
  }

  void _add(EvidenceEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeAt(0);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // 스토어가 닫힐 때: 비우고 더는 서명·알림 안 함. ChangeNotifier.dispose는 안 불러서 늦게 떨어지는 위젯 구독도 안전
  void close() {
    clear();
    _disposed = true;
  }
}
