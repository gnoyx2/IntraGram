import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart' show DartSha256;

import 'package:intragram/audit/signing.dart' show randomBytes;
import 'package:intragram/core/secure_bytes.dart';

String sha256B64(List<int> bytes) =>
    base64.encode(const DartSha256().hashSync(bytes).bytes);

// 흘러가는 바이트를 그대로 넘기며 SHA-256을 잼 (다시 읽지 않음). 끝까지 가야 onDigest가 불리고 중간에 끊기면 안 불림.
// 네이티브 첨부는 실제 타입이 Stream<Uint8List>라 그대로 transform하면 공변 타입 검사에서 던져서 cast로 감쌈
Stream<List<int>> sha256Tap(
  Stream<List<int>> source,
  void Function(String digestB64) onDigest,
) {
  final sink = const DartSha256().newHashSink();
  var failed = false;
  return source.cast<List<int>>().transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, out) {
        sink.add(chunk);
        out.add(chunk);
      },
      handleError: (error, stack, out) {
        failed = true;
        out.addError(error, stack);
      },
      handleDone: (out) {
        sink.close();
        if (!failed) onDigest(base64.encode(sink.hashSync().bytes));
        out.close();
      },
    ),
  );
}

// 짧은 메시지는 그냥 해시하면 사전 대입으로 내용이 드러남: 16바이트 salt를 섞고 그 salt는 바로 버림.
// 소각 뒤엔 이 기기도 증적만으로 본문을 되찾거나 추측을 확인 못 함. 본문 바이트는 여기서만 잠깐 쓰고 덮음
String saltedCommitment(String domain, List<Object?> fields) {
  final body = utf8.encode(jsonEncode(<Object?>[domain, ...fields]));
  final salt = randomBytes(16);
  final input = Uint8List(salt.length + body.length)
    ..setAll(0, salt)
    ..setAll(salt.length, body);
  try {
    return sha256B64(input);
  } finally {
    SecureBytes.wipe(input);
    SecureBytes.wipe(body);
    SecureBytes.wipe(salt);
  }
}
