import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_actions.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import '_harness.dart';

void main() {
  testWidgets('home screen renders identity, conversations and peers', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true, unread: 2))
      ..upsertConversation(conv('c2', secure: true, sas: '111222'));

    await tester.pumpWidget(h.wrap(const HomeScreen()));
    await tester.pump();

    expect(find.text('Intragram'), findsOneWidget);
    expect(find.text('me-host-10'), findsOneWidget);
    expect(find.text('bob-owl-22'), findsWidgets);
    expect(find.byIcon(Icons.gpp_good), findsOneWidget); // c1은 검증됨
    expect(find.byIcon(Icons.gpp_maybe), findsOneWidget); // c2는 미검증
    expect(find.byType(Badge), findsOneWidget); // c1에 안 읽은 메시지
  });

  testWidgets('manual connect dialog rejects a public IP inline', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byTooltip('Connect by IP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // AppAlertDialog는 플랫폼에 따라 CupertinoAlertDialog와 AlertDialog로 갈리므로 제목 문구로 확인함
    expect(find.text('Connect by IP'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '8.8.8.8');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('local network'), findsOneWidget);
  });

  testWidgets('home lists a discovered peer', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(h.store),
          linkRegistryProvider.overrideWithValue(h.registry),
          appIdentityProvider.overrideWithValue(h.identity),
          discoveryControllerProvider.overrideWith(
            () => _StaticDiscovery([
              PeerDevice(
                peerId: 'p1',
                alias: 'red-lynx-88',
                platform: 'Windows',
                host: '192.168.1.50',
                port: 7890,
                seenAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('red-lynx-88'), findsOneWidget);
    expect(find.textContaining('192.168.1.50'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'red-lynx-88'), findsOneWidget);
  });

  // 뒤로(예측형 포함)·Esc로 연결 중 창을 닫아도 취소: 나중에 연결이 끝나도 대화를 열지 않음
  testWidgets('backing out of the connecting dialog cancels opening the chat', (
    tester,
  ) async {
    final gate = Completer<String>();
    final h = Harness(
      registryBuilder: (store, identity) =>
          _SlowRegistry(gate, store: store, identity: identity),
    );
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(
      h.wrap(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => connectAndOpenPeer(
              context,
              ref,
              PeerDevice(
                peerId: 'p1',
                alias: 'red-lynx-88',
                platform: 'Windows',
                host: '192.168.1.50',
                port: 7890,
                seenAt: DateTime(2026, 1, 1),
              ),
            ),
            child: const Text('connect'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('connect'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    gate.complete('c1');
    await tester.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.text('connect'), findsOneWidget);
  });
}

class _StaticDiscovery extends DiscoveryController {
  _StaticDiscovery(this._peers);
  final List<PeerDevice> _peers;
  @override
  List<PeerDevice> build() => _peers;
}

class _SlowRegistry extends LinkRegistry {
  _SlowRegistry(this._gate, {required super.store, required super.identity})
    : super(crypto: CryptoEngine());

  final Completer<String> _gate;

  @override
  Future<String> connectToPeer(PeerDevice peer, {bool verifyPeerId = true}) =>
      _gate.future;
}
