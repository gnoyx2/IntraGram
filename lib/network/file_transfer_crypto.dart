import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_chunks.dart';

part 'file_transfer_decrypt.dart';

// 파일 전송 청크에 AEAD를 씌우는 프레이밍 레이어. PeerLink/CryptoSession을 import
// 안 하고 함수 타입(SealChunk/OpenChunk)으로만 통신해서 독립 테스트 가능
// 레코드: [4바이트 BE 길이][12바이트 nonce][16바이트 mac][ciphertext].
// 밑 전송이 경계와 무관하게 쪼개도 decryptChunks가 버퍼링해서 다시 자름
// 청크마다 AAD [version, transferId, attemptId, chunkIndex, totalBytes]를
// 인증해서 재사용/순서 바꿔치기를 막고, 레코드가 빠지거나(짧은 EOF) 더 오면 즉시 던짐

typedef SealChunk =
    Future<({Uint8List nonce, Uint8List cipher, Uint8List mac})> Function(
      Uint8List plaintext, {
      required Uint8List aad,
    });

typedef OpenChunk =
    Future<Uint8List> Function({
      required Uint8List nonce,
      required Uint8List cipher,
      required Uint8List mac,
      required Uint8List aad,
    });

const int _kLengthPrefixBytes = 4;
const int _kNonceBytes = 12;
const int _kMacBytes = 16;
const int _kMinRecordBody = _kNonceBytes + _kMacBytes; // 빈 ciphertext 허용

// 평문 totalBytes를 kFileChunkBytes로 나눴을 때 기대 레코드 개수. 0이면 레코드 0개 (빈 파일 계약)
int _expectedChunkCount(int totalBytes) {
  if (totalBytes <= 0) return 0;
  final full = totalBytes ~/ kFileChunkBytes;
  final remainder = totalBytes % kFileChunkBytes;
  return full + (remainder > 0 ? 1 : 0);
}

int _expectedChunkLength(int chunkIndex, int totalBytes) {
  final full = totalBytes ~/ kFileChunkBytes;
  final remainder = totalBytes % kFileChunkBytes;
  if (chunkIndex < full) return kFileChunkBytes;
  if (chunkIndex == full && remainder > 0) return remainder;
  return kFileChunkBytes; // 나머지가 없어 딱 떨어지는 경우(remainder==0)
}

// 양쪽이 같은 transferId/attemptId/totalBytes로 독립적으로 재구성해야 tag가 맞음
Uint8List _chunkAad({
  required String transferId,
  required String attemptId,
  required int chunkIndex,
  required int totalBytes,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<dynamic>[
      kProtocolVersion,
      transferId,
      attemptId,
      chunkIndex,
      totalBytes,
    ]),
  ),
);

// 평문을 고정 청크로 다시 자르고 조각마다 seal로 봉인해 길이-접두 레코드로 내보냄. 끝까지 돈 뒤 봉인한 평문 총합이
// totalBytes와 다르면 던짐 (offer 이후 로컬 파일이 바뀌어 약속한 크기와 어긋나는 걸 wire로 나가기 전에 잡음)
Stream<List<int>> encryptChunks(
  Stream<List<int>> plain,
  SealChunk seal, {
  required String transferId,
  required String attemptId,
  required int totalBytes,
}) async* {
  var chunkIndex = 0;
  var sealedBytes = 0;
  await for (final piece in fixedSizeChunks(plain, kFileChunkBytes)) {
    sealedBytes += piece.length;
    final sealed = await seal(
      piece,
      aad: _chunkAad(
        transferId: transferId,
        attemptId: attemptId,
        chunkIndex: chunkIndex,
        totalBytes: totalBytes,
      ),
    );
    chunkIndex++;
    final header = ByteData(_kLengthPrefixBytes)
      ..setUint32(
        0,
        _kNonceBytes + _kMacBytes + sealed.cipher.length,
        Endian.big,
      );
    final builder = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(sealed.nonce)
      ..add(sealed.mac)
      ..add(sealed.cipher);
    yield builder.takeBytes();
  }
  if (sealedBytes != totalBytes) {
    throw StateError(
      'encryptChunks sealed $sealedBytes bytes but source declared '
      '$totalBytes',
    );
  }
}

// encryptChunks로 감쌌을 때 실제로 wire에 나가는 총 바이트 수. 포맷이 결정적이라 스트림을 돌려보지 않고 미리 정확히 계산됨
// send()가 이 값을 Content-Length로 선언해서 chunked encoding에
// 기대지 않고도 항상 맞음 (평문 크기로 잘못 선언해 끊기던 버그 재발 방지)
int encryptedFileLength(int plaintextSize) {
  if (plaintextSize <= 0) return 0;
  const recordOverhead = _kLengthPrefixBytes + _kNonceBytes + _kMacBytes;
  final fullChunks = plaintextSize ~/ kFileChunkBytes;
  final remainder = plaintextSize % kFileChunkBytes;
  final full = fullChunks * (recordOverhead + kFileChunkBytes);
  final tail = remainder > 0 ? recordOverhead + remainder : 0;
  return full + tail;
}
