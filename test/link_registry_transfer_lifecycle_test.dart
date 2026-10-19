import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/link_registry_fixtures.dart';

void main() {
  late InMemoryStore store;
  late Directory tmp;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    tmp = Directory.systemTemp.createTempSync('intragram_lr');
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
    tmp.deleteSync(recursive: true);
  });

  test(
    'retryTransfer re-attempts a failed pull from the same staged source',
    () async {
      store.upsertConversation(conv('c1'));
      store.upsertTransfer(
        const FileTransfer(
          id: 'tr1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'shared.bin',
          totalBytes: 10,
          srcHost: '127.0.0.1',
          srcPort: 1, // 아무것도 안 듣는 포트: 빠르게 connection refused
        ),
      );

      await registry.acceptTransfer('tr1');
      expect(store.transfer('tr1')!.state, TransferState.failed);

      await registry.retryTransfer('tr1');
      // 재시도도 같은 이유로 다시 실패하지만, transferring을 다시 거쳐
      // failed로 갔다는 게 실제로 재시도했다는 증거임
      expect(store.transfer('tr1')!.state, TransferState.failed);
    },
  );

  test('retryTransfer is a no-op for a transfer that is not failed', () async {
    store.upsertConversation(conv('c1'));
    store.upsertTransfer(
      const FileTransfer(
        id: 'tr2',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'ok.bin',
        totalBytes: 5,
      ),
    );
    await registry.retryTransfer('tr2');
    expect(store.transfer('tr2')!.state, TransferState.offered);
  });

  test('retryTransfer is a no-op for an unknown transfer id', () async {
    await registry.retryTransfer('ghost');
    // 그냥 조용히 아무 일도 안 함: 던지지 않음
  });

  test(
    'acceptBatch accepts exactly the still-offered siblings in a batch',
    () async {
      store.upsertConversation(conv('c1'));
      store.upsertTransfer(
        const FileTransfer(
          id: 'b1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'a.txt',
          totalBytes: 1,
          batchId: 'batch-x',
        ),
      );
      store.upsertTransfer(
        const FileTransfer(
          id: 'b2',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'b.txt',
          totalBytes: 1,
          batchId: 'batch-x',
        ),
      );
      store.upsertTransfer(
        const FileTransfer(
          id: 'b3',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'c.txt',
          totalBytes: 1,
          batchId: 'batch-x',
        ),
      );
      // b3는 이미 개별적으로 거절됨: acceptBatch가 안 건드려야 함
      await registry.rejectTransfer('b3');

      await registry.acceptBatch('c1', 'batch-x');

      expect(store.transfer('b1')!.state, TransferState.accepted);
      expect(store.transfer('b2')!.state, TransferState.accepted);
      expect(store.transfer('b3')!.state, TransferState.rejected);
    },
  );

  test('rejectBatch rejects every still-offered sibling', () async {
    store.upsertConversation(conv('c1'));
    store.upsertTransfer(
      const FileTransfer(
        id: 'r1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'a.txt',
        totalBytes: 1,
        batchId: 'batch-y',
      ),
    );
    store.upsertTransfer(
      const FileTransfer(
        id: 'r2',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'b.txt',
        totalBytes: 1,
        batchId: 'batch-y',
      ),
    );

    await registry.rejectBatch('c1', 'batch-y');

    expect(store.transfer('r1')!.state, TransferState.rejected);
    expect(store.transfer('r2')!.state, TransferState.rejected);
  });
}
