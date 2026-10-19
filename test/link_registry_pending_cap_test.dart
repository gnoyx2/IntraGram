import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/test_identities.dart';

// hello 전(미인증) 인바운드 소켓 상한: 전체 상한, 그리고 한 host가 전부 독식하지 못하게 하는 host별
// 상한. hello를 안 보내는 소켓을 열어 두기만 해도 다른 기기의 연결이 막히는 걸 늦춤
void main() {
  late InMemoryStore store;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: testIdentity('a'),
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
  });

  // [host]에서 온 hello 없는 소켓 하나를 registry에 넘김. registry가 바로 닫았으면 true
  Future<bool> refused(String host, int port) async {
    final wire = StreamChannelController<dynamic>();
    var done = false;
    wire.local.stream.listen((_) {}, onDone: () => done = true);
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: host,
      remotePort: port,
    );
    await pumpEventQueue();
    return done;
  }

  test('one host cannot hold more than its share of pending sockets', () async {
    final outcomes = <bool>[
      for (var i = 0; i < kMaxPendingHandshakesPerHost + 3; i++)
        await refused('192.168.1.66', 5000 + i),
    ];

    expect(outcomes.where((closed) => closed), hasLength(3));
    expect(store.conversations, hasLength(kMaxPendingHandshakesPerHost));
    expect(await refused('192.168.1.67', 5000), isFalse, reason: 'other host');
    expect(store.conversations, hasLength(kMaxPendingHandshakesPerHost + 1));
  });

  test('many hosts still stop at the overall cap', () async {
    for (var i = 0; i < kMaxPendingHandshakes; i++) {
      expect(await refused('192.168.1.${100 + i}', 5000), isFalse);
    }

    expect(await refused('192.168.1.200', 5000), isTrue);
    expect(store.conversations, hasLength(kMaxPendingHandshakes));
  });

  // [host]에서 온 소켓을 받게 하고, 받아졌으면 바로 끊어 미인증 슬롯을 비움. registry가 거부했으면 true
  Future<bool> flick(String host) async {
    final wire = StreamChannelController<dynamic>();
    var closedByRegistry = false;
    wire.local.stream.listen((_) {}, onDone: () => closedByRegistry = true);
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: host,
      remotePort: 5000,
    );
    await pumpEventQueue();
    final refusedNow = closedByRegistry;
    if (!refusedNow) {
      await wire.local.sink.close();
      await pumpEventQueue();
    }
    return refusedNow;
  }

  test('one host is limited in how often it can connect', () async {
    var now = DateTime(2026);
    registry.debugNow = () => now;
    for (var i = 0; i < kMaxInboundPerWindow; i++) {
      expect(await flick('192.168.1.66'), isFalse, reason: 'attempt $i');
    }

    expect(await flick('192.168.1.66'), isTrue, reason: 'over the rate limit');
    expect(await flick('192.168.1.67'), isFalse, reason: 'another host');

    now = now.add(kInboundWindow + const Duration(seconds: 1));
    expect(await flick('192.168.1.66'), isFalse, reason: 'the window passed');
  });

  test('many hosts together are limited in how often they connect', () async {
    var now = DateTime(2026);
    registry.debugNow = () => now;
    for (var i = 0; i < kMaxInboundPerWindowAllHosts; i++) {
      // host마다 한 번씩이라 host별 상한엔 안 걸림: 주소를 여러 개 쓰는 기기를 흉내 냄
      final host = '192.168.${1 + i ~/ 200}.${1 + i % 200}';
      expect(await flick(host), isFalse, reason: 'attempt $i');
    }

    expect(await flick('192.168.9.9'), isTrue, reason: 'over the overall rate');

    now = now.add(kInboundWindow + const Duration(seconds: 1));
    expect(await flick('192.168.9.9'), isFalse, reason: 'the window passed');
  });

  test('the rate window slides: only recent connections count', () async {
    final start = DateTime(2026);
    var now = start;
    registry.debugNow = () => now;
    const half = kMaxInboundPerWindow ~/ 2;
    for (var i = 0; i < half; i++) {
      await flick('192.168.1.66');
    }
    now = start.add(kInboundWindow - const Duration(seconds: 1));
    for (var i = 0; i < half; i++) {
      await flick('192.168.1.66');
    }

    // 첫 절반은 창 밖으로 나갔고 뒤 절반만 남음: 그 위로 절반이 더 들어올 수 있음
    now = start.add(kInboundWindow + const Duration(seconds: 1));
    for (var i = 0; i < half; i++) {
      expect(await flick('192.168.1.66'), isFalse, reason: 'attempt $i');
    }
    expect(await flick('192.168.1.66'), isTrue);
  });

  test('hosts that went quiet are forgotten', () async {
    var now = DateTime(2026);
    registry.debugNow = () => now;
    for (var i = 0; i < 5; i++) {
      await flick('192.168.1.${100 + i}');
    }
    expect(registry.debugTrackedInboundHosts, 5);

    now = now.add(kInboundWindow + const Duration(seconds: 1));
    await flick('192.168.1.200');

    expect(registry.debugTrackedInboundHosts, 1);
  });

  test('disposing the registry forgets who connected', () async {
    await flick('192.168.1.66');
    expect(registry.debugTrackedInboundHosts, 1);

    await registry.disposeAll();

    expect(registry.debugTrackedInboundHosts, 0);
  });

  test('refused attempts are not counted against the host', () async {
    final start = DateTime(2026);
    var now = start;
    registry.debugNow = () => now;
    for (var i = 0; i < kMaxInboundPerWindow; i++) {
      await flick('192.168.1.66');
    }
    now = start.add(const Duration(seconds: 1));
    for (var i = 0; i < kMaxInboundPerWindow + 6; i++) {
      expect(await flick('192.168.1.66'), isTrue, reason: 'hammering');
    }

    // 처음 접속들이 창 밖으로 나가면, 그 사이 두드린 시도는 세지 않으니 바로 다시 받아 줌
    now = start.add(kInboundWindow + const Duration(milliseconds: 500));
    expect(await flick('192.168.1.66'), isFalse);
  });

  test('a slot frees once one of the host sockets is gone', () async {
    final wires = <StreamChannelController<dynamic>>[];
    for (var i = 0; i < kMaxPendingHandshakesPerHost; i++) {
      final wire = StreamChannelController<dynamic>()
        ..local.stream.listen((_) {});
      await registry.acceptInbound(
        wire.foreign,
        remoteHost: '192.168.1.66',
        remotePort: 5000 + i,
      );
      wires.add(wire);
    }
    expect(await refused('192.168.1.66', 6000), isTrue);

    await wires.first.local.sink.close();
    await pumpEventQueue();

    expect(await refused('192.168.1.66', 6001), isFalse);
  });
}
