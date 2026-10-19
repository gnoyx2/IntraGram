import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/crypto_engine.dart';

Future<(CryptoSession, CryptoSession)> _pair() async {
  final engine = CryptoEngine();
  final a = await engine.createSession();
  final b = await engine.createSession();
  await a.completeHandshake(b.publicKeyBase64);
  await b.completeHandshake(a.publicKeyBase64);
  return (a, b);
}

void main() {
  test('both sides derive the same key and exchange a frame', () async {
    final (a, b) = await _pair();
    expect(a.isReady, isTrue);
    expect(b.isReady, isTrue);

    final sealed = await a.seal(<String, dynamic>{
      'k': 'msg',
      'text': 'hi ivy',
    }, seq: 0);
    final opened = await b.open(
      nonceB64: sealed.nonce,
      cipherB64: sealed.cipher,
      macB64: sealed.mac,
      seq: 0,
    );
    expect(opened['text'], 'hi ivy');
  });

  test('both sides derive the same 6-digit SAS fingerprint', () async {
    final (a, b) = await _pair();
    expect(a.sasDigits, isNotNull);
    expect(a.sasDigits!.length, 6);
    expect(RegExp(r'^\d{6}$').hasMatch(a.sasDigits!), isTrue);
    expect(a.sasDigits, b.sasDigits);
  });

  test('unrelated sessions get different SAS fingerprints', () async {
    final (a, _) = await _pair();
    final (c, _) = await _pair();
    expect(a.sasDigits, isNot(c.sasDigits));
  });

  test('an all-zero peer key (low-order point) is rejected', () async {
    final engine = CryptoEngine();
    final a = await engine.createSession();
    await expectLater(
      a.completeHandshake(base64.encode(Uint8List(32))),
      throwsA(isA<SecurityException>()),
    );
    expect(a.isReady, isFalse);
  });

  test('a malformed peer key length is rejected', () async {
    final engine = CryptoEngine();
    final a = await engine.createSession();
    await expectLater(
      a.completeHandshake(base64.encode(Uint8List(16))),
      throwsA(isA<FormatException>()),
    );
  });

  test('a tampered ciphertext will not open', () async {
    final (a, b) = await _pair();
    final sealed = await a.seal(<String, dynamic>{'x': 1}, seq: 0);
    final flipped = sealed.cipher[0] == 'A' ? 'B' : 'A';
    final broken = flipped + sealed.cipher.substring(1);

    await expectLater(
      b.open(
        nonceB64: sealed.nonce,
        cipherB64: broken,
        macB64: sealed.mac,
        seq: 0,
      ),
      throwsA(anything),
    );
  });

  test('a nonce that is not the seq will not open', () async {
    final (a, b) = await _pair();
    final sealed = await a.seal(<String, dynamic>{'x': 1}, seq: 0);
    final otherNonce = base64.encode(Uint8List(12)..[11] = 7);

    await expectLater(
      b.open(
        nonceB64: otherNonce,
        cipherB64: sealed.cipher,
        macB64: sealed.mac,
        seq: 0,
      ),
      throwsA(isA<SecurityException>()),
    );
  });

  test('a tampered seq (associated data) will not open', () async {
    final (a, b) = await _pair();
    final sealed = await a.seal(<String, dynamic>{'x': 1}, seq: 0);

    await expectLater(
      b.open(
        nonceB64: sealed.nonce,
        cipherB64: sealed.cipher,
        macB64: sealed.mac,
        seq: 1, // 공격자가 seq만 고쳐서 재전송한 상황을 흉내냄
      ),
      throwsA(anything),
    );
  });

  test('an unrelated session cannot open the frame', () async {
    final (a, _) = await _pair();
    final (_, c) = await _pair();
    final sealed = await a.seal(<String, dynamic>{'x': 1}, seq: 0);

    await expectLater(
      c.open(
        nonceB64: sealed.nonce,
        cipherB64: sealed.cipher,
        macB64: sealed.mac,
        seq: 0,
      ),
      throwsA(anything),
    );
  });

  test('destroy makes the session throw on use and clears the SAS', () async {
    final (a, _) = await _pair();
    a.destroy();
    expect(a.sasDigits, isNull);
    await expectLater(
      a.seal(<String, dynamic>{'x': 1}, seq: 0),
      throwsStateError,
    );
  });

  group('deriveKeyFromPin (vault PIN)', () {
    Future<List<int>> derive(String pin, List<int> salt) async =>
        (await CryptoEngine.deriveKeyFromPin(pin, salt)).extractBytes();

    test('is deterministic per (pin, salt) and 32 bytes', () async {
      final salt = List<int>.filled(16, 7);
      final a = await derive('2468', salt);
      final b = await derive('2468', salt);
      expect(a, b);
      expect(a, hasLength(32));
    });

    test('a different salt or pin yields a different key', () async {
      final a = await derive('2468', List<int>.filled(16, 1));
      final otherSalt = await derive('2468', List<int>.filled(16, 2));
      final otherPin = await derive('1111', List<int>.filled(16, 1));
      expect(otherSalt, isNot(a));
      expect(otherPin, isNot(a));
    });
  });
}
