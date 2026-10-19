import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_auth.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 작은 위수 점(8-torsion)을 공개키로 쓰면 아무나 임의 메시지에 유효한 서명을 만들 수 있어서(항등원이면
// R=[s]B, S=s) 그 해시인 peerId를 누구나 "증명"함: 신원 키로 받지 않음. 그 점들을 구현의 상수를 보지 않고
// BigInt Edwards 산술로 직접 구해서(랜덤 점 P의 [L]P는 8-torsion 원소) 전부 거부되는지 봄

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l =
    (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final BigInt _d = (_p - BigInt.from(121665)) * _inv(BigInt.from(121666)) % _p;

typedef _Point = (BigInt x, BigInt y);

BigInt _inv(BigInt v) => (v % _p).modInverse(_p);

_Point _add(_Point a, _Point b) {
  final t = _d * a.$1 * b.$1 * a.$2 * b.$2 % _p;
  return (
    (a.$1 * b.$2 + b.$1 * a.$2) * _inv(BigInt.one + t) % _p,
    (a.$2 * b.$2 + a.$1 * b.$1) * _inv(BigInt.one - t) % _p,
  );
}

_Point _mul(_Point point, BigInt k) {
  var result = (BigInt.zero, BigInt.one);
  var addend = point;
  for (var scalar = k; scalar > BigInt.zero; scalar >>= 1) {
    if (scalar.isOdd) result = _add(result, addend);
    addend = _add(addend, addend);
  }
  return result;
}

// y에 대응하는 곡선 위의 점(없으면 null)
_Point? _decompress(BigInt y) {
  final x2 = (y * y - BigInt.one) * _inv(_d * y * y + BigInt.one) % _p;
  var x = x2.modPow((_p + BigInt.from(3)) >> 3, _p);
  if (x * x % _p != x2) {
    x = x * BigInt.two.modPow((_p - BigInt.one) >> 2, _p) % _p;
  }
  return x * x % _p == x2 ? (x, y) : null;
}

// 곡선의 8-torsion 점 전부
Set<_Point> _torsion() {
  final found = <_Point>{(BigInt.zero, BigInt.one)};
  for (var y = 2; found.length < 8 && y < 300; y++) {
    final point = _decompress(BigInt.from(y));
    if (point == null) continue;
    final t = _mul(point, _l);
    for (var cur = t; found.add(cur); cur = _add(cur, t)) {}
  }
  return found;
}

// 32바이트 little-endian y에 부호 비트(bit 255)를 붙인 인코딩
Uint8List _encode(BigInt y, {required int sign}) {
  final out = Uint8List(32);
  var v = y;
  for (var i = 0; i < 32; i++) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  out[31] |= sign << 7;
  return out;
}

void main() {
  test('every 8-torsion point is a small-order key, in any encoding', () {
    final points = _torsion();
    expect(points, hasLength(8));

    for (final (_, y) in points) {
      for (final sign in [0, 1]) {
        expect(isSmallOrderKey(_encode(y, sign: sign)), isTrue, reason: '$y');
        if (y < BigInt.from(19)) {
          // y ≥ p로 적은 비정규 인코딩도 같은 점을 가리킴
          expect(isSmallOrderKey(_encode(y + _p, sign: sign)), isTrue);
        }
      }
    }
  });

  test('honest identity keys are never small-order', () async {
    for (final tag in testIdentityTags) {
      expect(
        isSmallOrderKey(testIdentity(tag).publicKey!),
        isFalse,
        reason: tag,
      );
    }
    expect(isSmallOrderKey((await AppIdentity.create()).publicKey!), isFalse);
  });

  test('a listener refuses a hello that claims a small-order key', () async {
    final weakKey = _encode(BigInt.one, sign: 0); // 항등원
    final wire = StreamChannelController<dynamic>();
    final store = InMemoryStore()..upsertConversation(conv('cB', 'peer'));
    addTearDown(store.dispose);
    final link = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: store,
      identity: testIdentity('b', alias: 'host'),
      crypto: await CryptoEngine().createSession(),
    );
    addTearDown(link.close);
    final attacker = await ScriptedPeer.create(
      AppIdentity.generate(),
      wire.local,
    );
    await link.start();

    attacker.sendDialerHello(peerId: peerIdOfKey(weakKey), claimedKey: weakKey);
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(attacker.frames, isEmpty, reason: 'nothing is signed for it');
  });
}
