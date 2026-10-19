import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/free_space.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/link_registry_fixtures.dart';

// 받는 쪽 디스크가 모자라면 '알 수 없는 오류' 대신 공간 부족으로 알리고, 선언 크기가 남은 공간을
// 넘으면 받기 시작 전에 멈춤

void main() {
  test('a full disk while writing is reported as diskFull', () {
    for (final code in [28, 112, 39]) {
      expect(
        classifyTransferError(
          FileSystemException('write failed', '/x', OSError('full', code)),
        ),
        'diskFull',
      );
    }
    expect(
      classifyTransferError(
        const FileSystemException('denied', '/x', OSError('denied', 13)),
      ),
      'unknown',
    );
  });

  test(
    'free space matches what df reports for the same folder',
    () async {
      final free = freeBytesAt(Directory.systemTemp.path);
      final df = await Process.run('df', ['-k', Directory.systemTemp.path]);
      final avail = int.parse(
        (df.stdout as String).trim().split('\n').last.split(RegExp(r'\s+'))[3],
      );
      expect(free, isNotNull);
      // df와 앱이 묻는 순간 사이에 다른 프로세스가 쓸 수 있어 1% 안에서만 맞춤
      expect((free! - avail * 1024).abs(), lessThan(avail * 1024 ~/ 100 + 1));
    },
    skip: Platform.isMacOS || Platform.isLinux ? false : 'needs df',
  );

  test('an offer larger than the free space fails before any byte is '
      'written', () async {
    final store = InMemoryStore()..upsertConversation(conv('c1'));
    final tmp = Directory.systemTemp.createTempSync('intragram_full');
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
      tmp.deleteSync(recursive: true);
    });
    final free = freeBytesAt(tmp.path);
    if (free == null) return; // 이 플랫폼은 남은 공간을 모름: 확인 없이 받음
    store.upsertTransfer(
      FileTransfer(
        id: 't1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'huge.bin',
        totalBytes: free + (1 << 40),
      ),
    );

    await registry.acceptTransfer('t1');

    final t = store.transfer('t1')!;
    expect(t.state, TransferState.failed);
    expect(t.error, 'diskFull');
    expect(tmp.listSync(), isEmpty, reason: 'no .part was reserved');
  });
}
