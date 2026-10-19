import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/in_memory_store_fixtures.dart';

void main() {
  late InMemoryStore store;

  setUp(() {
    store = InMemoryStore();
    store.upsertConversation(conversation('c1'));
  });

  tearDown(() => store.dispose());

  test('applyReadReceipt marks our outgoing message as read', () {
    store.addMessage(
      EphemeralMessage(
        id: 'o1',
        conversationId: 'c1',
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: 'me',
        createdAt: DateTime(2026, 1, 1),
        text: 'hi',
        delivery: DeliveryState.sent,
      ),
    );
    store.applyReadReceipt('o1', 'peer');
    expect(store.messages('c1').single.delivery, DeliveryState.read);
    expect(store.messages('c1').single.readBy, {'peer'});
  });

  test('a late read receipt does not hide a failed delivery', () {
    store.addMessage(
      EphemeralMessage(
        id: 'partial',
        conversationId: 'c1',
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: 'me',
        createdAt: DateTime(2026, 1, 1),
        text: 'partial',
        delivery: DeliveryState.failed,
      ),
    );

    store.applyReadReceipt('partial', 'one-reader');

    expect(store.messageById('partial')?.delivery, DeliveryState.failed);
    expect(store.messageById('partial')?.readBy, {'one-reader'});
  });

  test('secureWipe empties everything but leaves the store usable', () {
    fakeAsync((async) {
      store.addMessage(incoming('m3', ttl: 30));
      store.markIncomingRead('c1');

      store.secureWipe();
      expect(store.conversations, isEmpty);
      expect(store.messages('c1'), isEmpty);

      // 대기 중인 burn 타이머가 소각된 스토어에 발동하면 안 됨
      async.elapse(const Duration(seconds: 60));

      store.upsertConversation(conversation('c2'));
      expect(store.conversations, hasLength(1));
    });
  });

  test('watchRoom emits the current list then updates', () {
    fakeAsync((async) {
      final seen = <int>[];
      final sub = store.watchRoom('c1').listen((list) => seen.add(list.length));
      async.flushMicrotasks();
      store.addMessage(incoming('m4'));
      async.flushMicrotasks();
      expect(seen, <int>[0, 1]);
      sub.cancel();
    });
  });

  test('peer typing auto-clears after the idle timeout', () {
    fakeAsync((async) {
      store.setPeerTyping('c1', typing: true);
      expect(store.conversation('c1')!.peerTyping, isTrue);

      async.elapse(const Duration(seconds: 3));
      expect(store.conversation('c1')!.peerTyping, isTrue);

      async.elapse(const Duration(seconds: 4)); // kTypingIdleTimeout(6s) 경과
      expect(store.conversation('c1')!.peerTyping, isFalse);
    });
  });

  test('a fresh typing signal re-arms the idle timeout', () {
    fakeAsync((async) {
      store.setPeerTyping('c1', typing: true);
      async.elapse(const Duration(seconds: 5));
      store.setPeerTyping('c1', typing: true); // 갱신: 타이머 재시작
      async.elapse(const Duration(seconds: 4));
      expect(store.conversation('c1')!.peerTyping, isTrue);
      async.elapse(const Duration(seconds: 3)); // 갱신 후 7초
      expect(store.conversation('c1')!.peerTyping, isFalse);
    });
  });

  test('applyReaction stacks multiple emoji per person and removes one', () {
    store.addMessage(incoming('rx1'));

    store.applyReaction('rx1', 'bob', '👍', on: true);
    expect(store.messages('c1').single.reactions, {
      'bob': {'👍'},
    });

    store.applyReaction('rx1', 'bob', '❤️', on: true); // 같은 사람의 두 번째 emoji
    expect(store.messages('c1').single.reactions, {
      'bob': {'👍', '❤️'},
    });

    store.applyReaction('rx1', 'ann', '👍', on: true);
    expect(store.messages('c1').single.reactions, {
      'bob': {'👍', '❤️'},
      'ann': {'👍'},
    });

    store.applyReaction('rx1', 'bob', '😀', on: false); // 건 적 없어서 no-op
    expect(store.messages('c1').single.reactions, {
      'bob': {'👍', '❤️'},
      'ann': {'👍'},
    });

    store.applyReaction('rx1', 'bob', '👍', on: false);
    expect(store.messages('c1').single.reactions, {
      'bob': {'❤️'},
      'ann': {'👍'},
    });
  });

  test('addSystemMessage adds a local note and leaves unread alone', () {
    store.addSystemMessage(
      'c1',
      const SystemEvent(SystemEventKind.disconnected),
    );
    final msgs = store.messages('c1');
    expect(msgs.single.kind, MessageKind.system);
    expect(msgs.single.systemEvent?.kind, SystemEventKind.disconnected);
    expect(store.conversation('c1')!.unread, 0);
  });
}
