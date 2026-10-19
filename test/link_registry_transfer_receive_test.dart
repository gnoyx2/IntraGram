import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/link_registry_fixtures.dart';

Stream<List<int>> bytes(int total, {int chunk = 8192}) async* {
  var sent = 0;
  while (sent < total) {
    final n = (total - sent) < chunk ? (total - sent) : chunk;
    yield List<int>.filled(n, 1);
    sent += n;
  }
}

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

  test('acceptTransfer sanitises a traversal filename', () async {
    store.upsertConversation(conv('c1'));
    store.upsertTransfer(
      const FileTransfer(
        id: 't1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: '../../../../Users/victim/.zshrc',
        totalBytes: 10,
      ),
    );

    await registry.acceptTransfer('t1');

    final t = store.transfer('t1')!;
    expect(t.state, TransferState.accepted);
    expect(t.localPath, isNotNull);
    expect(p.isWithin(tmp.path, t.localPath!), isTrue);
    // 폴더 밖으로 못 나가고, 숨김 설정 파일로도 안 남음
    expect(p.basename(t.localPath!), '_.zshrc');
  });

  test('receiveTransfer rejects an unknown transfer id', () async {
    final ok = await registry.receiveTransfer(
      transferId: 'ghost',
      attemptId: 'ghost',
      token: 'irrelevant', // 수락된 적 없어서 토큰 검사 전에 거부됨
      body: Stream<List<int>>.value(const [1, 2, 3]),
      headerDeclaredSize: 3,
    );
    expect(ok, isFalse);
  });

  test(
    'an un-accepted incoming offer never writes to disk — queue only',
    () async {
      store.upsertConversation(conv('c1'));
      store.upsertTransfer(
        const FileTransfer(
          id: 'q1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'unwanted.bin',
          totalBytes: 100,
        ),
      );

      // 사용자가 수락을 누르기 전에 피어가 바이트를 POST함
      final ok = await registry.receiveTransfer(
        transferId: 'q1',
        attemptId: 'q1',
        token: 'irrelevant', // 수락된 적 없어서 토큰 검사 전에 거부됨
        body: bytes(100),
        headerDeclaredSize: 100,
      );

      expect(ok, isFalse, reason: 'no accept => rejected at the door');
      expect(store.transfer('q1')!.state, TransferState.offered);
      expect(tmp.listSync(), isEmpty, reason: 'nothing landed in the save dir');
    },
  );

  test(
    'receiveTransfer aborts when the peer exceeds its declared size',
    () async {
      store.upsertConversation(conv('c1'));
      store.upsertTransfer(
        const FileTransfer(
          id: 't2',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'invoice.pdf',
          totalBytes: 1024, // 1 KB라 해놓고
        ),
      );
      await registry.acceptTransfer('t2');
      final dest = store.transfer('t2')!.localPath!;

      final ok = await registry.receiveTransfer(
        transferId: 't2',
        attemptId: 't2',
        token: registry.debugIncoming.debugPushTokenFor('t2')!,
        body: bytes(4 * 1024 * 1024), // 4 MB를 보냄
        headerDeclaredSize: 1024,
      );

      expect(ok, isFalse);
      expect(store.transfer('t2')!.state, TransferState.failed);
      expect(File(dest).existsSync(), isFalse);
    },
  );

  test('receiveTransfer writes a within-declaration file', () async {
    store.upsertConversation(conv('c1'));
    store.upsertTransfer(
      const FileTransfer(
        id: 't3',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'ok.bin',
        totalBytes: 5000,
      ),
    );
    await registry.acceptTransfer('t3');
    final dest = store.transfer('t3')!.localPath!;

    final ok = await registry.receiveTransfer(
      transferId: 't3',
      attemptId: 't3',
      token: registry.debugIncoming.debugPushTokenFor('t3')!,
      body: bytes(5000),
      headerDeclaredSize: 5000,
    );

    expect(ok, isTrue);
    expect(store.transfer('t3')!.state, TransferState.complete);
    expect(File(dest).lengthSync(), 5000);
  });

  test('cancelTransfer aborts a mid-flight push receive and deletes the '
      'partial file', () async {
    store.upsertConversation(conv('c1'));
    store.upsertTransfer(
      const FileTransfer(
        id: 'tc1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'big.bin',
        totalBytes: 1024 * 1024,
      ),
    );
    await registry.acceptTransfer('tc1');
    final dest = store.transfer('tc1')!.localPath!;

    // 첫 청크가 나가자마자 취소: receive()가 다음 청크에서 멈춰야 함
    Stream<List<int>> cancellingBody() async* {
      yield List<int>.filled(8192, 1);
      registry.cancelTransfer('tc1');
      for (var i = 0; i < 200; i++) {
        yield List<int>.filled(8192, 1);
      }
    }

    final ok = await registry.receiveTransfer(
      transferId: 'tc1',
      attemptId: 'tc1',
      token: registry.debugIncoming.debugPushTokenFor('tc1')!,
      body: cancellingBody(),
      headerDeclaredSize: 1024 * 1024,
    );

    expect(ok, isFalse);
    expect(store.transfer('tc1')!.state, TransferState.cancelled);
    expect(File(dest).existsSync(), isFalse);
  });
}
