import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:stream_channel/stream_channel.dart';

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
    'offerFilesFromPaths queues each present file with a batch label',
    () async {
      final wire = StreamChannelController<dynamic>();
      wire.local.stream.listen((_) {});
      await registry.acceptInbound(
        wire.foreign,
        remoteHost: '192.168.1.9',
        remotePort: 7890,
      );
      final id = store.conversations.single.id;

      File(p.join(tmp.path, 'a.txt')).writeAsStringSync('aaa');
      File(p.join(tmp.path, 'b.txt')).writeAsStringSync('bbbbb');
      await registry.offerFilesFromPaths(id, <String>[
        p.join(tmp.path, 'a.txt'),
        p.join(tmp.path, 'b.txt'),
        p.join(tmp.path, 'gone.txt'), // 없는 경로라 건너뜀
      ]);

      final outgoing = store.transfers
          .where((t) => t.direction == TransferDirection.outgoing)
          .toList();
      expect(outgoing, hasLength(2));
      expect(
        outgoing.map((t) => t.batchLabel),
        containsAll(<String>['1 / 2', '2 / 2']),
      );
      expect(outgoing.map((t) => t.totalBytes), containsAll(<int>[3, 5]));
      expect(
        outgoing.map((t) => t.batchId).toSet(),
        hasLength(1),
        reason: 'both files in the batch share one batchId',
      );
      expect(outgoing.first.batchId, isNotNull);
    },
  );

  test('a single dropped file gets no batch label', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );
    final id = store.conversations.single.id;

    File(p.join(tmp.path, 'solo.txt')).writeAsStringSync('x');
    await registry.offerFilesFromPaths(id, <String>[
      p.join(tmp.path, 'solo.txt'),
    ]);

    final outgoing = store.transfers.single;
    expect(outgoing.direction, TransferDirection.outgoing);
    expect(outgoing.batchLabel, isNull);
  });

  test(
    'cancelling an offered-but-unaccepted outgoing transfer just drops it',
    () async {
      final wire = StreamChannelController<dynamic>();
      wire.local.stream.listen((_) {});
      await registry.acceptInbound(
        wire.foreign,
        remoteHost: '192.168.1.9',
        remotePort: 7890,
      );
      final convId = store.conversations.single.id;

      await registry.offerInlineBytes(
        convId,
        'note.txt',
        Uint8List.fromList(List<int>.filled(10, 1)),
        mime: 'text/plain',
      );
      final id = store.transfers.single.id;
      expect(store.transfer(id)!.state, TransferState.offered);

      registry.cancelTransfer(id);

      expect(store.transfer(id)!.state, TransferState.cancelled);
      // 취소를 두 번 불러도(피어가 늦게 accept를 보내는 등) 안전함: 이미
      // cancelled라 가드에 걸려 조용히 무시됨
      registry.cancelTransfer(id);
      expect(store.transfer(id)!.state, TransferState.cancelled);
    },
  );

  test('a single-file offer has no batchId and is unaffected', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );
    final convId = store.conversations.single.id;

    File(p.join(tmp.path, 'solo2.txt')).writeAsStringSync('x');
    await registry.offerFilesFromPaths(convId, <String>[
      p.join(tmp.path, 'solo2.txt'),
    ]);

    expect(store.transfers.single.batchId, isNull);
  });

  test('offerInlineBytes stages a RAM transfer with no localPath', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );
    final id = store.conversations.single.id;

    await registry.offerInlineBytes(
      id,
      'voice-note.m4a',
      Uint8List.fromList(List<int>.filled(200, 7)),
      mime: 'audio/mp4',
      voice: true,
    );

    final outgoing = store.transfers.single;
    expect(outgoing.direction, TransferDirection.outgoing);
    expect(outgoing.localPath, isNull, reason: 'RAM source — nothing on disk');
    expect(outgoing.mimeType, 'audio/mp4');
    expect(outgoing.voice, isTrue);
    expect(outgoing.totalBytes, 200);
  });
}
