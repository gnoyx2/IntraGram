import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/network/crypto_engine.dart';

void main() {
  test('an owned key zeroes its buffer on destroy', () {
    final buffer = Uint8List.fromList(List<int>.filled(32, 0xAB));
    final key = ownedSecretKeyFrom(buffer);
    expect(key.bytes, everyElement(0xAB));
    key.destroy();
    expect(buffer, everyElement(0));
  });

  test('a buffer handed back by an isolate is zeroed too', () async {
    final buffer = await Isolate.run(
      () => Uint8List.fromList(List<int>.filled(32, 0xCD)),
    );
    ownedSecretKeyFrom(buffer).destroy();
    expect(buffer, everyElement(0));
  });

  test('taking over a library key copies it and drops the original', () async {
    final library = SecretKeyData(List<int>.filled(32, 7));
    final owned = await takeSecretKey(library);
    expect(library.hasBeenDestroyed, isTrue);
    expect(owned.bytes, everyElement(7));
    expect((owned.bytes as SensitiveBytes).overwriteWhenDestroyed, isTrue);
  });

  test('handshake session keys are app-owned and erasable', () async {
    final engine = CryptoEngine();
    final a = await engine.createSession();
    final b = await engine.createSession();
    await a.completeHandshake(b.publicKeyBase64);
    final keys = a.debugSessionKeys;
    expect(keys, hasLength(4));
    for (final key in keys) {
      final bytes = (key! as SecretKeyData).bytes as SensitiveBytes;
      expect(bytes.overwriteWhenDestroyed, isTrue);
    }
    a.destroy();
    b.destroy();
  });
}
