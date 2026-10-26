import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:intragram/audit/anchor_receipt.dart';
import 'package:intragram/audit/attestation.dart';
import 'package:intragram/audit/batch.dart';
import 'package:intragram/audit/merkle.dart';

// issued: 내가 서명함, verified: 상대 서명과 바인딩을 내가 확인함, rejected: 받았지만 확인에 실패함 (배치에 안 넣음)
enum EvidenceStatus { issued, verified, rejected }

@immutable
final class EvidenceEntry {
  EvidenceEntry({
    required this.attestation,
    required this.status,
    required Uint8List leafSalt,
    this.conversationId,
    this.transferId,
    this.batchNo,
    this.batchIndex,
  }) : leafSalt = immutableBytes(leafSalt);

  final SignedAttestation attestation;
  final EvidenceStatus status;

  // Merkle 잎 salt 16바이트. 이 증적의 증명을 내보낼 때만 같이 나감
  final Uint8List leafSalt;

  // 이 기기 대화·전송 id: 화면 필터·배지용 로컬 표시라 서명에 안 들어감 (원장 번호로 안 씀)
  final String? conversationId;
  final String? transferId;
  final int? batchNo;
  final int? batchIndex;

  Uint8List get leaf => merkleLeaf(leafSalt, attestation.leafPayload);

  EvidenceEntry inBatch(int no, int index) => EvidenceEntry(
    attestation: attestation,
    status: status,
    leafSalt: leafSalt,
    conversationId: conversationId,
    transferId: transferId,
    batchNo: no,
    batchIndex: index,
  );
}

// 봉인한 배치: 증명을 만들 잎 해시와 잎마다 사건 id를 같이 둠
@immutable
final class MerkleBatch {
  MerkleBatch({
    required this.header,
    required List<Uint8List> leaves,
    required List<String> eventIds,
    this.anchor,
  }) : leaves = List.unmodifiable(leaves.map(immutableBytes)),
       eventIds = List.unmodifiable(eventIds);

  final BatchHeader header;
  final List<Uint8List> leaves;
  final List<String> eventIds;

  // 검증까지 끝낸 증인 앵커만 붙음
  final AnchorReceipt? anchor;

  MerkleBatch withAnchor(AnchorReceipt receipt) => MerkleBatch(
    header: header,
    leaves: leaves,
    eventIds: eventIds,
    anchor: receipt,
  );
}

// 내가 증인으로 관측한 상대 기기의 배치. 같은 기기·번호에 다른 루트가 오면 conflict가 true가 됨 (상대 기기가 원장을 바꿔 제시함)
@immutable
final class WitnessRecord {
  const WitnessRecord({
    required this.peerId,
    required this.batchNo,
    required this.root,
    required this.witnessedAtMs,
    this.conflict = false,
  });

  final String peerId;
  final int batchNo;
  final String root;
  final int witnessedAtMs;
  final bool conflict;
}
