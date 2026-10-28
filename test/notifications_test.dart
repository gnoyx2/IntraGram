import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_navigator.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/notifications.dart';
import 'package:intragram/l10n/locale_controller.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

// 언어를 영어로 고정: 실제 시스템 로케일에 좌우되면 한국어 로케일 머신에서
// body/title 기대값이 깨짐 (제네릭 알림 문구가 언어를 탐)
class _FixedLang extends LocaleController {
  @override
  AppLang build() => AppLang.en;
}

class _FakeNotifications extends NotificationService {
  final calls = <({String title, String body, String conversationId})>[];
  var permissionAsks = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermissionOnce() async => permissionAsks++;

  @override
  Future<void> show({
    required String title,
    required String body,
    required String conversationId,
    required String channelName,
    required String channelDescription,
  }) async {
    calls.add((title: title, body: body, conversationId: conversationId));
    channels.add(channelName);
  }

  final channels = <String>[];
}

Conversation _conv(String id) => Conversation(
  id: id,
  peerAlias: 'blue-otter-9',
  peerPlatform: 'Linux',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
);

EphemeralMessage _incoming(String id, String text) => EphemeralMessage(
  id: id,
  conversationId: 'c1',
  direction: MessageDirection.incoming,
  kind: MessageKind.text,
  senderAlias: 'blue-otter-9',
  createdAt: DateTime(2026, 1, 1),
  text: text,
  delivery: DeliveryState.sent,
);

void main() {
  test('notification bridge fires only when the app is backgrounded', () async {
    final store = InMemoryStore();
    addTearDown(store.dispose);
    store.upsertConversation(_conv('c1'));

    final fake = _FakeNotifications();
    final container = ProviderContainer(
      overrides: [
        inMemoryStoreProvider.overrideWithValue(store),
        notificationServiceProvider.overrideWithValue(fake),
        // 실제 HapticFeedback은 이 bare container에 없는 플랫폼 채널이 필요해서 no-op으로 바꿈 (NotificationService와 같은 seam)
        foregroundMessageHapticProvider.overrideWithValue(() async {}),
        localeControllerProvider.overrideWith(_FixedLang.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(notificationBridgeProvider); // 구독을 활성화

    // 알림 권한은 첫 화면이 아니라 앞에 있을 때 온 첫 메시지에서 물음
    expect(fake.permissionAsks, 0);
    store.appInForeground = true;
    store.addMessage(_incoming('m1', 'while looking'));
    await pumpEventQueue();
    expect(fake.calls, isEmpty);
    expect(fake.permissionAsks, 1);

    store.appInForeground = false;
    store.addMessage(_incoming('m2', 'while away'));
    await pumpEventQueue();
    expect(fake.calls, hasLength(1));
    // 발신자 alias도 메시지 본문도 절대 안 실림: 항상 이 제네릭 문구뿐
    expect(fake.calls.single.body, 'New message');
    expect(fake.calls.single.title, 'Intragram');
    // Android 알림 설정 화면의 채널 이름도 앱 언어 문구
    expect(fake.channels.single, 'Messages');
  });

  test('system messages never notify', () async {
    final store = InMemoryStore();
    addTearDown(store.dispose);
    store.upsertConversation(_conv('c1'));

    final fake = _FakeNotifications();
    final container = ProviderContainer(
      overrides: [
        inMemoryStoreProvider.overrideWithValue(store),
        notificationServiceProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    container.read(notificationBridgeProvider);

    store.appInForeground = false;
    store.addSystemMessage(
      'c1',
      const SystemEvent(SystemEventKind.disconnected),
    );
    await pumpEventQueue();
    expect(fake.calls, isEmpty);
  });

  group('ConversationOpener — notification tap routing', () {
    test('opens the chat immediately when no PIN gate is up', () {
      final opened = <String>[];
      ConversationOpener(push: opened.add, gateUp: () => false).open('c1');
      expect(opened, <String>['c1']);
    });

    test('holds the tap while the PIN gate is up, replays after unlock', () {
      final opened = <String>[];
      var gateUp = true;
      final opener = ConversationOpener(push: opened.add, gateUp: () => gateUp);

      opener.open('c1');
      expect(opened, isEmpty);

      gateUp = false;
      opener.gateCleared();
      expect(opened, <String>['c1']);
    });

    test('gateCleared with no pending tap does nothing', () {
      final opened = <String>[];
      ConversationOpener(push: opened.add, gateUp: () => false).gateCleared();
      expect(opened, isEmpty);
    });
  });
}
