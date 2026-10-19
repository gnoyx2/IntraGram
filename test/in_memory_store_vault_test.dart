import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import 'support/in_memory_store_fixtures.dart';

void main() {
  late InMemoryStore store;

  setUp(() {
    store = InMemoryStore();
    store.upsertConversation(conversation('c1'));
  });

  tearDown(() => store.dispose());

  group('vault snapshot / hydrate', () {
    test('toSnapshot honours the keepMessages scope', () {
      store.addMessage(incoming('s1'));
      store.upsertTransfer(
        const FileTransfer(
          id: 'x1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'f.bin',
          totalBytes: 1,
          state: TransferState.complete,
        ),
      );

      final noMsgs = store.toSnapshot(
        const VaultSettings(enabled: true, keepMessages: false),
      );
      expect(noMsgs.messages, isEmpty);
      expect(noMsgs.transfers, hasLength(1));
    });

    test(
      'toSnapshot skips burned/system messages and incomplete transfers',
      () {
        store.addMessage(incoming('keep'));
        store.addMessage(
          EphemeralMessage(
            id: 'sys',
            conversationId: 'c1',
            direction: MessageDirection.incoming,
            kind: MessageKind.system,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'joined',
            delivery: DeliveryState.sent,
          ),
        );
        store.upsertTransfer(
          const FileTransfer(
            id: 'offered',
            conversationId: 'c1',
            direction: TransferDirection.incoming,
            fileName: 'pending.bin',
            totalBytes: 10,
          ),
        );

        final snap = store.toSnapshot(const VaultSettings(enabled: true));
        expect(snap.messages.map((m) => m.id), <String>['keep']);
        expect(snap.transfers, isEmpty);
      },
    );

    test('setVaultOptOut drops the whole conversation from the snapshot', () {
      store.addMessage(incoming('m1'));
      expect(
        store.toSnapshot(const VaultSettings(enabled: true)).conversations,
        hasLength(1),
      );

      store.setVaultOptOut('c1', value: true);
      final snap = store.toSnapshot(const VaultSettings(enabled: true));
      expect(snap.conversations, isEmpty);
      expect(snap.messages, isEmpty);
    });

    test('hydrate restores an archive and drops expired-timer messages', () {
      final other = InMemoryStore();
      addTearDown(other.dispose);

      final snap = VaultSnapshot(
        settings: const VaultSettings(enabled: true),
        conversations: [
          Conversation(
            id: 'a1',
            peerAlias: 'peer',
            peerPlatform: 'Linux',
            transport: PeerTransport.app,
            startedAt: DateTime(2026, 1, 1),
          ),
        ],
        messages: [
          EphemeralMessage(
            id: 'live',
            conversationId: 'a1',
            direction: MessageDirection.incoming,
            kind: MessageKind.text,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'still here',
            delivery: DeliveryState.sent,
          ),
          EphemeralMessage(
            id: 'expired',
            conversationId: 'a1',
            direction: MessageDirection.incoming,
            kind: MessageKind.text,
            senderAlias: 'peer',
            createdAt: DateTime(2026, 1, 1),
            text: 'gone',
            ttlSeconds: 5,
            burnAt: DateTime(2020, 1, 1),
            delivery: DeliveryState.sent,
          ),
        ],
        transfers: const [],
      );

      other.hydrate(snap, now: DateTime(2026, 6, 1));

      expect(other.messages('a1').map((m) => m.id), <String>['live']);
      expect(other.conversation('a1'), isNotNull);
    });

    test('hydrate re-arms a countdown that has not finished yet', () {
      fakeAsync((async) {
        final other = InMemoryStore();
        addTearDown(other.dispose);
        final now = DateTime(2026, 1, 1, 12);

        other.hydrate(
          VaultSnapshot(
            settings: const VaultSettings(enabled: true),
            conversations: [
              Conversation(
                id: 'a1',
                peerAlias: 'peer',
                peerPlatform: 'Linux',
                transport: PeerTransport.app,
                startedAt: now,
              ),
            ],
            messages: [
              EphemeralMessage(
                id: 'ticking',
                conversationId: 'a1',
                direction: MessageDirection.incoming,
                kind: MessageKind.text,
                senderAlias: 'peer',
                createdAt: now,
                text: 'soon gone',
                ttlSeconds: 30,
                burnAt: now.add(const Duration(seconds: 10)),
                delivery: DeliveryState.sent,
              ),
            ],
            transfers: const [],
          ),
          now: now,
        );

        expect(other.messages('a1'), hasLength(1));
        async.elapse(const Duration(seconds: 11));
        expect(
          other.messages('a1'),
          isEmpty,
          reason: 'timer resumed and fired',
        );
      });
    });

    // 시간대가 바뀌어도(여행·설정) 남은 소각 시간이 시차만큼 늘지 않게 UTC로 저장함
    test('message times are saved in UTC and read back as local', () {
      final burnAt = DateTime.now().add(const Duration(seconds: 30));
      final json = incoming('t1', ttl: 30).copyWith(burnAt: burnAt).toJson();
      expect(json['createdAt'], endsWith('Z'));
      expect(json['burnAt'], endsWith('Z'));

      final back = EphemeralMessage.fromJson(json);
      expect(back.burnAt, burnAt);
      expect(back.createdAt, DateTime(2026, 1, 1));

      // 오프셋 없는 옛 형식은 저장한 시간대를 몰라서 이미 지난 것으로 봄
      final old = EphemeralMessage.fromJson({
        ...json,
        'burnAt': burnAt.toIso8601String(),
      });
      expect(old.burnAt!.isBefore(DateTime.now()), isTrue);
    });
  });
}
