import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

Conversation conv(
  String id, {
  bool secure = false,
  bool verified = false,
  String? sas,
  int unread = 0,
  PeerTransport transport = PeerTransport.app,
}) => Conversation(
  id: id,
  peerAlias: 'bob-owl-22',
  peerPlatform: 'macOS',
  transport: transport,
  startedAt: DateTime(2026, 1, 1),
  online: true,
  secure: secure,
  localVerified: verified,
  peerVerified: verified,
  sas: sas,
  unread: unread,
);

EphemeralMessage msg({
  required String id,
  required MessageDirection dir,
  MessageKind kind = MessageKind.text,
  String? text,
  String? transferId,
  String? replyToId,
  int ttl = 0,
  DateTime? burnAt,
  DateTime? createdAt,
}) => EphemeralMessage(
  id: id,
  conversationId: 'c1',
  direction: dir,
  kind: kind,
  senderAlias: dir == MessageDirection.outgoing ? 'me' : 'bob-owl-22',
  createdAt: createdAt ?? DateTime(2026, 1, 1, 10, 30),
  text: text,
  transferId: transferId,
  replyToId: replyToId,
  ttlSeconds: ttl,
  burnAt: burnAt,
  delivery: DeliveryState.sent,
);

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.pump();
  }
}

// 패닉이 클립보드를 비움: 응답 없는 진짜 채널에 막히지 않게 호출만 기록함
void mockPrivacyChannel(List<String> calls) {
  const channel = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call.method);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

class Harness {
  // registryBuilder는 registry를 테스트 전용 하위 타입으로 바꿔 끼우는 seam
  // (패닉 테스트가 disposeAll을 Completer로 쥐려고 씀, 기본은 진짜 registry)
  Harness({
    this.identityStore,
    LinkRegistry Function(InMemoryStore store, AppIdentity identity)?
    registryBuilder,
  }) : store = InMemoryStore(),
       identity = AppIdentity(
         peerId: '0' * 32,
         alias: 'me-host-10',
         platform: 'Linux',
       ) {
    registry =
        registryBuilder?.call(store, identity) ??
        LinkRegistry(store: store, crypto: CryptoEngine(), identity: identity);
  }

  final InMemoryStore store;
  final AppIdentity identity;
  final IdentityStore? identityStore;
  late final LinkRegistry registry;

  Widget wrap(
    Widget child, {
    List<Override> overrides = const <Override>[],
    GlobalKey<NavigatorState>? navigatorKey,
    TransitionBuilder? builder,
  }) {
    return ProviderScope(
      overrides: [
        inMemoryStoreProvider.overrideWithValue(store),
        linkRegistryProvider.overrideWithValue(registry),
        appIdentityProvider.overrideWithValue(identity),
        // 기본 IdentityStore()는 path_provider의 실제 플랫폼 채널을 타는데 위젯 테스트엔 그 핸들러가 없어서 응답이 진짜 이벤트 루프에서 옴.
        // FakeAsync 안의 pump만으론 안 끝나서 resolveDir seam으로 그 채널을 아예 안 타게 함
        identityStoreProvider.overrideWithValue(
          identityStore ??
              IdentityStore(resolveDir: () async => 'test-identity-dir'),
        ),
        tempSweepProvider.overrideWithValue(() async {}),
        ...overrides,
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        builder: builder,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: child,
      ),
    );
  }

  Future<void> dispose() async {
    await registry.disposeAll();
    store.dispose();
  }
}

// 썸네일 헤더 검사는 엔진 쪽 비동기라 실제 시간으로 한 번 돌려줘야 끝남
Future<void> settleThumbCheck(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
