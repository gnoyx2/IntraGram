import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/portal_guest.dart' show identity, kTestPortalToken;
import 'support/test_identities.dart';

// 프로토콜 v7(다이얼러 임시키 커밋-후-공개)은 v6 이하와 섞이지 않음: hello 단계에서 명시적으로
// 거부하고 링크를 닫음. 브라우저 상수와의 일치는 tool/browser_guard_test.js가 봄
void main() {
  test('the wire protocol is v7', () => expect(kProtocolVersion, '7'));

  Map<String, Object?> hello(String type, Object? version) => <String, Object?>{
    't': type,
    'v': ?version,
    'peerId': testPeerId('a'),
    'alias': 'old-peer',
    'platform': 'test',
    'cmt': base64.encode(List<int>.filled(32, 2)),
    'idk': base64.encode(testIdentity('a').publicKey!),
  };

  group('a hello from another protocol version is a mismatch', () {
    for (final type in <String>['hello', 'web_hello']) {
      for (final version in <Object?>['6', '5', '4', '3', '2', '8', '', null]) {
        test('$type v=$version', () {
          final parsed = InboundOuter.parse(jsonEncode(hello(type, version)));
          expect(parsed, isA<VersionMismatchOuter>());
        });
      }
    }

    test('the current version is accepted', () {
      final parsed = InboundOuter.parse(
        jsonEncode(hello('hello', kProtocolVersion)),
      );
      expect(parsed, isA<HelloOuter>());
    });
  });

  test('dialling an older peer leaves a version line in that chat', () async {
    final store = InMemoryStore();
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });
    final wire = StreamChannelController<dynamic>();
    wire.foreign.stream.listen((_) {});
    registry.debugDial = (_) async => wire.local;
    final id = await registry.connectManual(host: '192.168.1.20', port: 7890);
    await pumpEventQueue(times: 30);
    wire.foreign.sink.add(
      jsonEncode(<String, Object?>{...hello('hello', '6'), 'cmt': null}),
    );
    await pumpEventQueue(times: 60);

    // 안내 줄이 '연결 끊김'을 대신함 (두 줄 겹치지 않음)
    final lines = store.messages(id).map((m) => m.systemEvent?.kind);
    expect(lines, [SystemEventKind.protocolVersionMismatch]);
  });

  group('the registry refuses an older peer at hello', () {
    late InMemoryStore store;
    late LinkRegistry registry;
    late StreamChannelController<dynamic> wire;

    setUp(() async {
      store = InMemoryStore();
      registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: identity(),
      );
      wire = StreamChannelController<dynamic>();
      // 반대편이 듣고 있어야 링크의 sink.close()가 바로 끝남(안 그러면 2초 대기)
      wire.local.stream.listen((_) {});
      await registry.acceptInbound(
        wire.foreign,
        remoteHost: '192.168.1.20',
        requiredWebToken: () => kTestPortalToken,
      );
    });

    tearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });

    // v6은 직전 버전: 임시키를 hello에 바로 실어서 SAS 커밋이 없으므로 섞이면 안 됨
    for (final type in <String>['hello', 'web_hello']) {
      for (final version in <String>['6', '5', '3']) {
        // 모르는 기기가 연 연결이라 안내 줄을 남기면 아무 LAN 기기나 빈 대화를 쌓을 수 있음: 닫고 지움
        test('a v$version $type is closed and leaves no tile', () async {
          wire.local.sink.add(jsonEncode(hello(type, version)));
          await pumpEventQueue(times: 60);

          expect(store.conversations, isEmpty);
          expect(registry.appRoomId, isNull);
          expect(registry.portalRoomId, isNull);
        });
      }
    }
  });
}
