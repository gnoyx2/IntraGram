import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'test_identities.dart';

// registry가 닫았으면 closed가 켜지고, hangUp은 상대가 끊는 것 (hello를 안 보내는 인바운드 소켓 하나)
typedef InboundConn = ({
  Future<void> accepted,
  bool Function() closed,
  Future<void> Function() hangUp,
});

class AdmissionRig {
  AdmissionRig._(this.store, this.engine, this.registry);

  final InMemoryStore store;
  final CryptoEngine engine;
  final LinkRegistry registry;

  static AdmissionRig create() {
    final store = InMemoryStore();
    final engine = CryptoEngine();
    final registry = LinkRegistry(
      store: store,
      crypto: engine,
      identity: testIdentity('a'),
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });
    return AdmissionRig._(store, engine, registry);
  }

  // 기다리지 않음 (InboundConn.accepted로 기다림)
  InboundConn connect(String host, int port) {
    final wire = StreamChannelController<dynamic>();
    var closed = false;
    wire.local.stream.listen((_) {}, onDone: () => closed = true);
    final accepted = registry.acceptInbound(
      wire.foreign,
      remoteHost: host,
      remotePort: port,
    );
    return (
      accepted: accepted,
      closed: () => closed,
      hangUp: () => wire.local.sink.close(),
    );
  }

  // hosts마다 each개씩 전부 한꺼번에 넣고 등록된 수와 registry가 닫은 수를 돌려줌
  Future<({int kept, int refused})> flood(
    List<String> hosts, {
    required int each,
  }) async {
    final conns = [
      for (final host in hosts)
        for (var i = 0; i < each; i++) connect(host, 5000 + i),
    ];
    await Future.wait(conns.map((c) => c.accepted));
    await pumpEventQueue();
    final refused = conns.where((c) => c.closed()).length;
    return (kept: conns.length - refused, refused: refused);
  }
}
