import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:intragram/audit/batch.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/audit/signing.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart' show wireBytes, wireInt;

const String kAnchorDomain = 'intragram/anchor-receipt/v1';
const int _kMaxWireInt = 9007199254740991;

// 다른 기기(증인)가 '이 배치 루트를 이 시각에 봤다'고 서명한 외부 앵커. 증인도 같은 번호에 다른 루트가 오면 상충을 앎
@immutable
final class AnchorReceipt {
  AnchorReceipt({
    required this.batchNo,
    required this.leafCount,
    required Uint8List root,
    required Uint8List requesterKey,
    required Uint8List witnessKey,
    required this.witnessedAtMs,
    required this.nonce,
    required Uint8List signature,
  }) : root = immutableBytes(root),
       requesterKey = immutableBytes(requesterKey),
       witnessKey = immutableBytes(witnessKey),
       signature = immutableBytes(signature);

  final int batchNo;
  final int leafCount;
  final Uint8List root;
  final Uint8List requesterKey;
  final Uint8List witnessKey;
  final int witnessedAtMs;
  final String nonce;
  final Uint8List signature;

  String get witnessPeerId => peerIdOfKey(witnessKey);

  Uint8List get signedBytes => utf8.encode(
    jsonEncode(<Object>[
      kAnchorDomain,
      batchNo,
      leafCount,
      base64.encode(root),
      base64.encode(requesterKey),
      base64.encode(witnessKey),
      witnessedAtMs,
      nonce,
    ]),
  );

  // 이 배치 머리를 가리키는가 (번호·잎 수·루트·요청자 키가 다 같아야 함)
  bool binds(BatchHeader header) =>
      header.no == batchNo &&
      header.leafCount == leafCount &&
      bytesEqual(header.root, root) &&
      bytesEqual(header.signerKey, requesterKey);

  Future<bool> verify() async =>
      !bytesEqual(requesterKey, witnessKey) &&
      await verifyEd25519(
        message: signedBytes,
        signature: signature,
        key: witnessKey,
      );

  static Future<AnchorReceipt> witness(
    AppIdentity witness,
    BatchHeader header,
  ) async {
    if (!await header.verify() ||
        bytesEqual(witness.publicKey ?? [], header.signerKey)) {
      throw ArgumentError('an external witness requires a valid signed batch');
    }
    final unsigned = AnchorReceipt(
      batchNo: header.no,
      leafCount: header.leafCount,
      root: header.root,
      requesterKey: header.signerKey,
      witnessKey: Uint8List.fromList(witness.publicKey!),
      witnessedAtMs: DateTime.now().millisecondsSinceEpoch,
      nonce: base64.encode(randomBytes(16)),
      signature: Uint8List(64),
    );
    return AnchorReceipt.fromWire(<String, dynamic>{
      ...unsigned.toWire(),
      'sg': base64.encode(await witness.sign(unsigned.signedBytes)),
    })!;
  }

  Map<String, dynamic> toWire() => <String, dynamic>{
    'no': batchNo,
    'n': leafCount,
    'rt': base64.encode(root),
    'rk': base64.encode(requesterKey),
    'wk': base64.encode(witnessKey),
    'wa': witnessedAtMs,
    'nc': nonce,
    'sg': base64.encode(signature),
  };

  static AnchorReceipt? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final no = wireInt(raw['no'], min: 1, max: _kMaxWireInt);
    final leafCount = wireInt(raw['n'], min: 1, max: 1 << 20);
    final root = wireBytes(raw['rt'], length: 32);
    final requester = wireBytes(raw['rk'], length: 32);
    final witness = wireBytes(raw['wk'], length: 32);
    final at = wireInt(raw['wa'], min: 0, max: _kMaxWireInt);
    final nonce = wireBytes(raw['nc'], length: 16);
    final sig = wireBytes(raw['sg'], length: 64);
    if (no == null ||
        leafCount == null ||
        root == null ||
        requester == null ||
        witness == null ||
        at == null ||
        nonce == null ||
        sig == null) {
      return null;
    }
    return AnchorReceipt(
      batchNo: no,
      leafCount: leafCount,
      root: root,
      requesterKey: requester,
      witnessKey: witness,
      witnessedAtMs: at,
      nonce: base64.encode(nonce),
      signature: sig,
    );
  }
}
