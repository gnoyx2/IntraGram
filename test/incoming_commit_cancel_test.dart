import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/in_memory_store_fixtures.dart';

// 마지막 바이트를 flush한 직후의 진행 콜백에서 취소를 끼워 넣음
class _CancelAtEofStore extends InMemoryStore {
  IncomingTransfers? incoming;
  bool cancelled = false;

  @override
  void updateTransfer(String id, FileTransfer Function(FileTransfer) update) {
    super.updateTransfer(id, update);
    final current = transfer(id);
    if (!cancelled &&
        current != null &&
        current.state == TransferState.transferring &&
        current.transferredBytes == current.totalBytes &&
        current.bytesPerSecond == 0) {
      cancelled = true;
      incoming!.cancelTransfer(id);
    }
  }
}

void main() {
  test('cancel at EOF never commits a completed file', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_commit_cancel_');
    final store = _CancelAtEofStore()..upsertConversation(conversation('c'));
    final incoming = IncomingTransfers(
      store: store,
      linkFor: (_) => null,
      gate: TransferConcurrencyGate(),
      chooseDirectory: (_) async => dir.path,
    );
    store.incoming = incoming;
    addTearDown(() async {
      await incoming.clear();
      store.dispose();
      await store.drainDisposals();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    store.upsertTransfer(
      const FileTransfer(
        id: 't',
        conversationId: 'c',
        direction: TransferDirection.incoming,
        fileName: 't.bin',
        totalBytes: 8,
        attemptId: 'a',
      ),
    );
    await incoming.accept('t');
    final received = await incoming.receive(
      transferId: 't',
      attemptId: 'a',
      token: incoming.debugPushTokenFor('t')!,
      body: Stream<List<int>>.value(const [1, 2, 3, 4, 5, 6, 7, 8]),
      headerDeclaredSize: 8,
    );
    await incoming.discard('t');

    expect(store.cancelled, isTrue);
    expect(received, isFalse);
    expect(store.transfer('t')!.state, TransferState.cancelled);
    expect(dir.listSync(), isEmpty);
  });
}
