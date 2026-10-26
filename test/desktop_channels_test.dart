import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/native_open.dart';
import 'package:intragram/core/notifications.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'ui/_harness.dart';

// Dart 쪽 분기만 봄: 실제 FlashWindowEx 플래그·포커스 판정·SHOpenFolderAndSelectItems는 Windows 실기 QA 몫
class _LockedAccess extends VaultAccessNotifier {
  @override
  VaultAccessState build() => const VaultLocked();
}

final _conversation = Conversation(
  id: 'c1',
  peerAlias: 'private-alias',
  peerPlatform: 'Windows',
  transport: PeerTransport.app,
  startedAt: DateTime(2026),
);

EphemeralMessage _incoming(String id, {bool file = false}) => EphemeralMessage(
  id: id,
  conversationId: 'c1',
  direction: MessageDirection.incoming,
  kind: file ? MessageKind.file : MessageKind.text,
  senderAlias: 'private-alias',
  createdAt: DateTime(2026),
  text: file ? null : 'private message',
  transferId: file ? id : null,
  delivery: DeliveryState.sent,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacy = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(privacy, (call) async {
      calls.add(call);
      return call.method == 'revealFile';
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(privacy, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('${platform.name} reveals unusual names unchanged through the native '
        'channel and never asks for missing folders', () async {
      debugDefaultTargetPlatformOverride = platform;
      final dir = Directory.systemTemp.createTempSync('ig_reveal_');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final name in [
        'a & b (한글).txt',
        'quote\'s "double" 100% #1.txt',
        '한글 폴더 파일 ✓.txt',
      ]) {
        calls.clear();
        final file = File('${dir.path}/$name')..writeAsStringSync('x');
        expect(await NativeOpen.revealInFolder(file.path), isTrue);
        expect(calls.single.method, 'revealFile');
        expect(calls.single.arguments, file.path);
      }
      // 지워진 파일이어도 폴더가 있으면 네이티브가 폴더를 엶. 폴더째 없으면 아예 안 부름
      calls.clear();
      expect(await NativeOpen.revealInFolder('${dir.path}/gone.txt'), isTrue);
      expect(calls.single.arguments, '${dir.path}/gone.txt');
      calls.clear();
      expect(await NativeOpen.revealInFolder('${dir.path}/no/x.txt'), isFalse);
      expect(calls, isEmpty);
    });
  }

  test('Windows asks for payload-free attention for messages and file '
      'offers only while away', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final store = InMemoryStore();
    addTearDown(store.dispose);
    store.upsertConversation(_conversation);
    final service = NotificationService();
    await service.init();
    final container = ProviderContainer(
      overrides: [
        inMemoryStoreProvider.overrideWithValue(store),
        notificationServiceProvider.overrideWithValue(service),
        foregroundMessageHapticProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    container.read(notificationBridgeProvider);
    store.appInForeground = true;
    store.addMessage(_incoming('m1'));
    store.addMessage(_incoming('f1', file: true));
    await pumpEventQueue();
    expect(calls, isEmpty);
    store.appInForeground = false;
    store.addMessage(_incoming('m2'));
    store.addMessage(_incoming('f2', file: true));
    await pumpEventQueue();
    expect(calls.map((c) => c.method), [
      'requestAttention',
      'requestAttention',
    ]);
    expect(calls.every((c) => c.arguments == null), isTrue);
    expect(service.isReady, isFalse); // 토스트 플러그인이 초기화되지 않은 상태임
  });

  // 포커스를 잃음(inactive)·최소화(hidden)·백그라운드(paused)는 모두 자리를 비운 것. 복귀(resumed)는 아님
  testWidgets(
    'Windows window states decide who asks for attention',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.store.upsertConversation(_conversation);
      final service = NotificationService();
      await tester.pumpWidget(
        h.wrap(
          const IntraGramApp(),
          overrides: [
            vaultAccessProvider.overrideWith(_LockedAccess.new),
            notificationServiceProvider.overrideWithValue(service),
            foregroundMessageHapticProvider.overrideWithValue(() async {}),
            roomHintBridgeProvider.overrideWith((ref) {}),
            screenshotBridgeProvider.overrideWith((ref) {}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      var id = 0;
      for (final (state, away) in [
        (AppLifecycleState.resumed, false),
        (AppLifecycleState.inactive, true),
        (AppLifecycleState.hidden, true),
        (AppLifecycleState.paused, true),
        (AppLifecycleState.hidden, true),
        (AppLifecycleState.inactive, true),
        (AppLifecycleState.resumed, false),
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        calls.clear();
        h.store.addMessage(_incoming('m${id++}', file: id.isEven));
        await tester.pump();
        expect(
          calls.where((c) => c.method == 'requestAttention'),
          hasLength(away ? 1 : 0),
          reason: state.name,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
