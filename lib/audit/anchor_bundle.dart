import 'dart:convert';

import 'package:meta/meta.dart';

import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/network/protocol.dart' show wireBytes, wireInt;

const String kAnchorBundleFormat = 'intragram-audit-anchor-bundle/v1';

// 붙여 넣은 문자열이 이보다 크면 파싱 전에 거절함 (단일 입력이 RAM을 과도하게 쓰지 못하게 막음)
const int _kMaxBundleChars = 4 * 1024 * 1024;

// 배치 하나에 든 증적 상한 (이 앱 장부가 한 배치에 담는 최대치). 넘으면 서명 검증을 과도하게 유발하므로 바로 거절함
const int _kMaxBundleEntries = EvidenceStore.maxEntries;

// 봉인한 배치 하나를 LAN 감사 게이트웨이나 오프라인 반출용 감사 번들(JSON)로 내보냄. only를 주면 해당 증적만 선택 공개하고
// 나머지 사건은 salt를 섞은 형제 해시로만 남아 내용을 짐작할 수 없음
String exportAnchorBundle(
  EvidenceStore store,
  MerkleBatch batch, {
  Set<String>? only,
}) {
  final entries = store.entries.where(
    (e) =>
        e.batchNo == batch.header.no &&
        (only == null || only.contains(e.attestation.eventId)),
  );
  final anchor = batch.anchor;
  return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'format': kAnchorBundleFormat,
    'batch': batch.header.toWire(),
    'anchor': ?anchor?.toWire(),
    'entries': [
      for (final e in entries)
        <String, dynamic>{
          'index': e.batchIndex,
          'salt': base64.encode(e.leafSalt),
          'attestation': e.attestation.toWire(),
          'proof': [
            for (final step in store.proofFor(e) ?? const [])
              base64.encode(step),
          ],
        },
    ],
  });
}

// 번들 검증 결과. ok는 배치 서명·포함된 모든 증적의 서명과 Merkle 증명·(있으면) 증인 앵커가 다 맞을 때만 true임
@immutable
final class BundleVerdict {
  const BundleVerdict({
    required this.ok,
    this.batchNo,
    this.leafCount = 0,
    this.entryCount = 0,
    this.validEntries = 0,
    this.batchSigned = false,
    this.anchored,
    this.anchorSigned = false,
    this.witnessPeerId,
    this.error,
  });

  final bool ok;
  final int? batchNo;
  final int leafCount;
  final int entryCount;
  final int validEntries;
  final bool batchSigned;

  // null: 외부 증인 신뢰 핀 미제공, true: 독립 확인한 증인 키와 서명까지 일치
  final bool? anchored;
  final bool anchorSigned;
  final String? witnessPeerId;

  // 형식 오류 사유 (필드 이름만, 값은 안 담음)
  final String? error;
}

Future<BundleVerdict> verifyAnchorBundle(
  String text, {
  String? expectedWitnessPeerId,
}) async {
  if (text.length > _kMaxBundleChars) {
    return const BundleVerdict(ok: false, error: 'size');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const BundleVerdict(ok: false, error: 'json');
  }
  if (decoded is! Map || decoded['format'] != kAnchorBundleFormat) {
    return const BundleVerdict(ok: false, error: 'format');
  }
  final header = BatchHeader.fromWire(decoded['batch']);
  final rawEntries = decoded['entries'];
  if (header == null || rawEntries is! List || rawEntries.isEmpty) {
    return const BundleVerdict(ok: false, error: 'batch');
  }
  if (rawEntries.length > _kMaxBundleEntries) {
    return const BundleVerdict(ok: false, error: 'entries');
  }
  final batchSigned = await header.verify();
  bool? anchored;
  var anchorSigned = false;
  String? witnessPeerId;
  var anchorValid = true;
  if (decoded['anchor'] != null) {
    final anchor = AnchorReceipt.fromWire(decoded['anchor']);
    witnessPeerId = anchor?.witnessPeerId;
    anchorValid =
        anchor != null && anchor.binds(header) && await anchor.verify();
    anchorSigned = anchorValid;
    if (expectedWitnessPeerId != null) {
      anchored = anchorValid && witnessPeerId == expectedWitnessPeerId;
    }
  } else if (expectedWitnessPeerId != null) {
    anchored = false;
  }
  var valid = 0;
  final indices = <int>{};
  final events = <String>{};
  for (final raw in rawEntries.take(header.leafCount)) {
    if (raw is! Map) continue;
    final index = wireInt(raw['index'], min: 0, max: header.leafCount - 1);
    final event = SignedAttestation.fromWire(raw['attestation'])?.eventId;
    if (index != null &&
        event != null &&
        indices.add(index) &&
        events.add(event) &&
        await _entryHolds(raw, header)) {
      valid++;
    }
  }
  return BundleVerdict(
    ok:
        batchSigned &&
        anchorValid &&
        anchored != false &&
        rawEntries.length <= header.leafCount &&
        valid == rawEntries.length,
    batchNo: header.no,
    leafCount: header.leafCount,
    entryCount: rawEntries.length,
    validEntries: valid,
    batchSigned: batchSigned,
    anchored: anchored,
    anchorSigned: anchorSigned,
    witnessPeerId: witnessPeerId,
  );
}

// 증적 하나: salt로 다시 만든 잎이 증명 경로를 따라 배치 루트에 닿고 서명도 맞아야 함 (싼 해시 검사를 먼저 해서
// 엉뚱한 항목엔 Ed25519 검사를 안 돌림)
Future<bool> _entryHolds(Object? raw, BatchHeader header) async {
  if (raw is! Map) return false;
  final attestation = SignedAttestation.fromWire(raw['attestation']);
  final salt = wireBytes(raw['salt'], length: 16);
  final index = wireInt(raw['index'], min: 0, max: header.leafCount - 1);
  final proof = raw['proof'];
  if (attestation == null || salt == null || index == null || proof is! List) {
    return false;
  }
  if (proof.length > 64) return false;
  final path = <List<int>>[];
  for (final step in proof) {
    final bytes = wireBytes(step, length: 32);
    if (bytes == null) return false;
    path.add(bytes);
  }
  return verifyMerkleProof(
        leaf: merkleLeaf(salt, attestation.leafPayload),
        index: index,
        leafCount: header.leafCount,
        path: path,
        root: header.root,
      ) &&
      await attestation.verify();
}
