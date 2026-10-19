import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/peer_auth.dart';

import 'support/test_identities.dart';

// 테스트가 쓰는 고정 신원 상수(시드·공개키·태그)가 서로 맞는지: 어긋나면 링크 핸드셰이크 테스트가
// 이유 모를 신원 거부로 깨지므로 여기서 먼저 잡음
void main() {
  for (final tag in testIdentityTags) {
    test('test identity $tag has a matching key and a tagged peerId', () async {
      final identity = testIdentity(tag);
      final key = identity.publicKey!;
      expect(key, hasLength(32));
      expect(identity.peerId, peerIdOfKey(key));
      expect(identity.peerId, hasLength(32));
      expect(identity.peerId[0], tag);

      final message = <int>[1, 2, 3];
      final signature = await identity.sign(message);
      expect(
        await verifyAuth(
          transcript: message,
          signature: signature,
          signerKey: key,
        ),
        isTrue,
        reason: 'the seed signs for the public key on file',
      );
    });
  }

  test('the peerId is the hash of the public key, so two keys differ', () {
    expect(testPeerId('a'), isNot(testPeerId('b')));
    expect(peerIdOfKey(List<int>.filled(32, 7)), hasLength(32));
  });

  test('a freshly created identity signs for its own peerId', () async {
    final identity = await AppIdentity.create();
    expect(identity.peerId, peerIdOfKey(identity.publicKey!));
    final signature = await identity.sign(<int>[9]);
    expect(
      await verifyAuth(
        transcript: <int>[9],
        signature: signature,
        signerKey: identity.publicKey!,
      ),
      isTrue,
    );
    expect(
      await verifyAuth(
        transcript: <int>[8],
        signature: signature,
        signerKey: identity.publicKey!,
      ),
      isFalse,
      reason: 'another message does not verify',
    );
  });

  test('an identity without a key cannot sign', () {
    final keyless = AppIdentity.generate();
    expect(keyless.publicKey, isNull);
    expect(() => keyless.sign(<int>[1]), throwsStateError);
  });

  test('rotateKey swaps in a fresh key and wipes the old seed', () async {
    final identity = testIdentity('b');
    final oldSeed = identity.debugSeed!;
    final oldKey = identity.publicKey!;
    expect(oldSeed.any((b) => b != 0), isTrue);

    await identity.rotateKey();

    expect(identity.publicKey, isNot(oldKey));
    expect(identity.peerId, peerIdOfKey(identity.publicKey!));
    expect(oldSeed.every((b) => b == 0), isTrue);
    expect(identity.debugSeed!.any((b) => b != 0), isTrue);
  });

  test('overlapping rotations still wipe the seed they replaced', () async {
    final identity = testIdentity('c');
    final first = identity.debugSeed!;

    await Future.wait(<Future<void>>[
      identity.rotateKey(),
      identity.rotateKey(),
    ]);

    expect(first.every((b) => b == 0), isTrue);
    expect(identity.peerId, peerIdOfKey(identity.publicKey!));
    expect(identity.debugSeed!.any((b) => b != 0), isTrue);
  });

  test('rotateKey on a keyless identity changes nothing', () async {
    final keyless = AppIdentity.generate();
    final peerId = keyless.peerId;

    await keyless.rotateKey();

    expect(keyless.peerId, peerId);
    expect(keyless.publicKey, isNull);
  });
}
