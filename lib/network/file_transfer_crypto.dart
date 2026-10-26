import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_chunks.dart';

part 'file_transfer_decrypt.dart';

// 파일 청크에 AEAD를 씌우는 프레이밍. PeerLink·CryptoSession 대신 함수 타입(SealChunk/OpenChunk)만 받아서 따로 테스트됨.
// 레코드 = [4바이트 BE 길이][12바이트 nonce][16바이트 mac][암호문]. AAD [version, transferId, attemptId, chunkIndex, totalBytes]로
// 레코드를 다른 전송·순서로 돌려쓰는 걸 막고, 빠지거나(짧은 EOF) 더 오면 바로 던짐

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

// 기대 레코드 수. 빈 파일이면 0개
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
  return kFileChunkBytes; // 딱 떨어지는 경우
}

// 양쪽이 같은 값으로 따로 만들어야 tag가 맞음
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

// 고정 크기로 다시 잘라 조각마다 봉인해 길이-접두 레코드로 내보냄. 다 돌고 나서 평문 총합이 totalBytes와 다르면 던짐
// (offer 뒤에 로컬 파일이 바뀐 걸 wire로 나가기 전에 잡음)
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

// 암호화했을 때 wire에 나가는 총 바이트 (형식이 결정적이라 미리 계산됨). send()가 Content-Length로 씀: 평문 크기로 잘못 선언해 끊기던 버그 방지
int encryptedFileLength(int plaintextSize) {
  if (plaintextSize <= 0) return 0;
  const recordOverhead = _kLengthPrefixBytes + _kNonceBytes + _kMacBytes;
  final fullChunks = plaintextSize ~/ kFileChunkBytes;
  final remainder = plaintextSize % kFileChunkBytes;
  final full = fullChunks * (recordOverhead + kFileChunkBytes);
  final tail = remainder > 0 ? recordOverhead + remainder : 0;
  return full + tail;
}
