import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/in_memory_store_fixtures.dart';

void main() {
  late InMemoryStore store;

  setUp(() {
    store = InMemoryStore();
    store.upsertConversation(conversation('c1'));
  });

  tearDown(() => store.dispose());

  test('markIncomingRead starts a countdown that later burns the message', () {
    fakeAsync((async) {
      store.addMessage(incoming('m1', ttl: 5));

      final transitioned = store.markIncomingRead('c1');
      expect(transitioned, <String>['m1']);
      expect(store.messages('c1').single.burnAt, isNotNull);

      async.elapse(const Duration(seconds: 4));
      expect(store.messages('c1'), hasLength(1));

      async.elapse(const Duration(seconds: 2));
      expect(store.messages('c1'), isEmpty);
    });
  });

  test('a timer burn emits a localBurns event for the peer', () {
    fakeAsync((async) {
      final burns = <String>[];
      final sub = store.localBurns.listen((e) => burns.add(e.messageId));

      store.addMessage(incoming('m1', ttl: 5));
      store.markIncomingRead('c1');
      async.elapse(const Duration(seconds: 6));

      expect(burns, <String>['m1']);
      sub.cancel();
    });
  });

  test('a burn frame removes the message immediately', () {
    store.addMessage(incoming('m2'));
    store.burnMessage('m2');
    expect(store.messages('c1'), isEmpty);
  });

  group('burn ceiling', () {
    test('a timered message burns at the ceiling if never read', () {
      fakeAsync((async) {
        store.addMessage(incoming('t1', ttl: 5));
        async.elapse(const Duration(hours: 23));
        expect(
          store.messages('c1'),
          hasLength(1),
          reason: 'ceiling not reached',
        );
        async.elapse(const Duration(hours: 2)); // kUnreadBurnCeiling(24h) 경과
        expect(store.messages('c1'), isEmpty);
      });
    });

    test('a ceiling burn still signals the peer', () {
      fakeAsync((async) {
        final burns = <String>[];
        final sub = store.localBurns.listen((e) => burns.add(e.messageId));
        store.addMessage(incoming('t2', ttl: 5));
        async.elapse(const Duration(hours: 25));
        expect(burns, <String>['t2']);
        sub.cancel();
      });
    });

    test('reading hands off: burns on the ttl, not the 24h ceiling', () {
      fakeAsync((async) {
        store.addMessage(incoming('t3', ttl: 30));
        async.elapse(const Duration(hours: 1)); // 1시간째 안 읽음
        expect(store.messages('c1'), hasLength(1));

        store.markIncomingRead('c1');
        async.elapse(const Duration(seconds: 31));
        expect(
          store.messages('c1'),
          isEmpty,
          reason: 'ttl countdown after read, not the ceiling',
        );
      });
    });

    test('a message with no timer never gets a ceiling', () {
      fakeAsync((async) {
        store.addMessage(incoming('t4')); // ttl 0
        async.elapse(const Duration(hours: 48));
        expect(store.messages('c1'), hasLength(1));
      });
    });
  });

  test('userDeletesMessage removes it locally and tells the peer', () {
    fakeAsync((async) {
      final burns = <String>[];
      final sub = store.localBurns.listen((e) => burns.add(e.messageId));
      store.addMessage(incoming('d1'));

      store.userDeletesMessage('d1');
      async.flushMicrotasks();

      expect(store.messages('c1'), isEmpty);
      expect(burns, <String>['d1']);
      sub.cancel();
    });
  });
}
