import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:intragram/audit/signing.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart' show wireBytes, wireInt;

const String kBatchDomain = 'intragram/merkle-batch/v1';
const int _kMaxWireInt = 9007199254740991;

// 이 기기가 서명한 배치 머리: 번호·잎 수·루트·봉인 시각. 합의가 없어서 '확정'이 아니라 이 기기의 커밋일 뿐
@immutable
final class BatchHeader {
  BatchHeader({
    required this.no,
    required this.leafCount,
    required Uint8List root,
    required this.sealedAtMs,
    required Uint8List signerKey,
    required Uint8List signature,
  }) : root = immutableBytes(root),
       signerKey = immutableBytes(signerKey),
       signature = immutableBytes(signature);

  final int no;
  final int leafCount;
  final Uint8List root;
  final int sealedAtMs;
  final Uint8List signerKey;
  final Uint8List signature;

  Uint8List get signedBytes => utf8.encode(
    jsonEncode(<Object>[
      kBatchDomain,
      no,
      leafCount,
      base64.encode(root),
      sealedAtMs,
      base64.encode(signerKey),
    ]),
  );

  Future<bool> verify() =>
      verifyEd25519(message: signedBytes, signature: signature, key: signerKey);

  static Future<BatchHeader> sign(
    AppIdentity identity, {
    required int no,
    required List<Uint8List> leaves,
  }) async {
    final unsigned = BatchHeader(
      no: no,
      leafCount: leaves.length,
      root: merkleRoot(leaves),
      sealedAtMs: DateTime.now().millisecondsSinceEpoch,
      signerKey: Uint8List.fromList(identity.publicKey!),
      signature: Uint8List(64),
    );
    return BatchHeader(
      no: no,
      leafCount: unsigned.leafCount,
      root: unsigned.root,
      sealedAtMs: unsigned.sealedAtMs,
      signerKey: unsigned.signerKey,
      signature: await identity.sign(unsigned.signedBytes),
    );
  }

  Map<String, dynamic> toWire() => <String, dynamic>{
    'no': no,
    'n': leafCount,
    'rt': base64.encode(root),
    'sa': sealedAtMs,
    'pk': base64.encode(signerKey),
    'sg': base64.encode(signature),
  };

  static BatchHeader? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final no = wireInt(raw['no'], min: 1, max: _kMaxWireInt);
    final leafCount = wireInt(raw['n'], min: 1, max: 1 << 20);
    final root = wireBytes(raw['rt'], length: 32);
    final sealedAt = wireInt(raw['sa'], min: 0, max: _kMaxWireInt);
    final key = wireBytes(raw['pk'], length: 32);
    final sig = wireBytes(raw['sg'], length: 64);
    if (no == null ||
        leafCount == null ||
        root == null ||
        sealedAt == null ||
        key == null ||
        sig == null) {
      return null;
    }
    return BatchHeader(
      no: no,
      leafCount: leafCount,
      root: root,
      sealedAtMs: sealedAt,
      signerKey: key,
      signature: sig,
    );
  }
}
