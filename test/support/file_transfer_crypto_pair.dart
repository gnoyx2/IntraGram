import 'dart:async';
import 'dart:typed_data';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

const testTransferId = 't1';
const testAttemptId = 'a1';

Future<(CryptoSession, CryptoSession)> pairSessions() async {
  final engine = CryptoEngine();
  final a = await engine.createSession();
  final b = await engine.createSession();
  await a.completeHandshake(b.publicKeyBase64);
  await b.completeHandshake(a.publicKeyBase64);
  return (a, b);
}

// chunks를 그대로 한 조각씩 내보내는 스트림 (하위 전송 계층이 원본 청킹과 무관한 크기로 바이트를 넘기는 상황 재현)
Stream<List<int>> streamOf(List<List<int>> chunks) async* {
  for (final c in chunks) {
    yield c;
  }
}

Future<List<int>> encryptForTest(
  CryptoSession sender,
  Uint8List plain, {
  String transferId = testTransferId,
  String attemptId = testAttemptId,
}) => encryptChunks(
  streamOf([plain]),
  sender.sealBytes,
  transferId: transferId,
  attemptId: attemptId,
  totalBytes: plain.length,
).expand((c) => c).toList();

Future<List<int>> decryptForTest(
  CryptoSession receiver,
  List<int> wire,
  int totalBytes, {
  String transferId = testTransferId,
  String attemptId = testAttemptId,
}) => decryptChunks(
  streamOf([wire]),
  receiver.openBytes,
  transferId: transferId,
  attemptId: attemptId,
  totalBytes: totalBytes,
).expand((c) => c).toList();
