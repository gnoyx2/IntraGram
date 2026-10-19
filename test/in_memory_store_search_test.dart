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

  group('searchMessages', () {
    test('matches text case-insensitively and skips non-text', () {
      store
        ..addMessage(incoming('a')) // text: 'secret'
        ..addMessage(
          EphemeralMessage(
            id: 'b',
            conversationId: 'c1',
            direction: MessageDirection.incoming,
            kind: MessageKind.system,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'SECRET join',
            delivery: DeliveryState.sent,
          ),
        )
        ..addMessage(
          EphemeralMessage(
            id: 'f', // 파일/음성 메시지는 검색 가능한 텍스트가 없음
            conversationId: 'c1',
            direction: MessageDirection.incoming,
            kind: MessageKind.file,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'secret.m4a',
            transferId: 't1',
            delivery: DeliveryState.sent,
          ),
        );

      final hits = store.searchMessages('SECRET').toList();
      expect(hits.map((h) => h.message.id), <String>['a']);
    });

    test('honours the conversationId filter and skips burned', () {
      store.upsertConversation(conversation('c2'));
      store
        ..addMessage(incoming('a'))
        ..addMessage(
          EphemeralMessage(
            id: 'c2m',
            conversationId: 'c2',
            direction: MessageDirection.incoming,
            kind: MessageKind.text,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'secret elsewhere',
            delivery: DeliveryState.sent,
          ),
        );

      expect(
        store
            .searchMessages('secret', conversationId: 'c1')
            .map((h) => h.message.id),
        <String>['a'],
      );

      store.burnMessage('a');
      expect(store.searchMessages('secret', conversationId: 'c1'), isEmpty);
    });
  });
}
