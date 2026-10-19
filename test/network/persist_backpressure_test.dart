import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

void main() {
  InMemoryStore seeded() => InMemoryStore()
    ..upsertConversation(
      Conversation(
        id: 'room',
        peerAlias: 'peer',
        peerPlatform: 'Linux',
        transport: PeerTransport.app,
        startedAt: DateTime(2026),
      ),
    )
    ..upsertTransfer(
      const FileTransfer(
        id: 'file',
        conversationId: 'room',
        direction: TransferDirection.incoming,
        fileName: 'test.bin',
        totalBytes: 100,
      ),
    );

  test('volatile events emit UI updates without scheduling saves', () {
    fakeAsync((clock) {
      final store = seeded();
      var saves = 0, rooms = 0, transfers = 0;
      store.onPersistableChange = () => saves++;
      final roomSub = store.watchConversations().listen((_) => rooms++);
      final transferSub = store.watchTransfers().listen((_) => transfers++);
      clock.flushMicrotasks();
      for (var i = 0; i < 40; i++) {
        store.setConversationOnline('room', online: i.isEven);
        store.setPeerTyping('room', typing: i.isEven);
        store.updateTransfer(
          'file',
          (t) => t.copyWith(transferredBytes: i, bytesPerSecond: i.toDouble()),
        );
        clock.elapse(const Duration(milliseconds: 250));
      }
      expect(saves, 0);
      expect(rooms, greaterThan(1));
      expect(transfers, greaterThan(1));
      store.updateTransfer(
        'file',
        (t) => t.copyWith(state: TransferState.complete),
      );
      clock.elapse(const Duration(seconds: 1));
      expect(saves, 1);
      roomSub.cancel();
      transferSub.cancel();
      store.dispose();
    });
  });

  test(
    'continuous durable changes flush every five seconds and then debounce',
    () {
      fakeAsync((clock) {
        final store = seeded();
        var saves = 0;
        store.onPersistableChange = () => saves++;
        for (var i = 1; i <= 40; i++) {
          store.setOutgoingTtl('room', i);
          clock.elapse(const Duration(milliseconds: 250));
          expect(saves, i ~/ 20);
        }
        store.setOutgoingTtl('room', 99);
        clock.elapse(const Duration(seconds: 1));
        expect(saves, 3);
        clock.elapse(const Duration(seconds: 5));
        expect(saves, 3);
        store.setOutgoingTtl('room', 100);
        store.stopPersisting();
        clock.elapse(const Duration(seconds: 6));
        expect(saves, 3);
        store.onPersistableChange = () => saves++;
        store.setOutgoingTtl('room', 101);
        store.dispose();
        clock.elapse(const Duration(seconds: 6));
        expect(saves, 3);
      });
    },
  );
}
