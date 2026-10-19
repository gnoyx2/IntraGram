import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/fake_file_source_channel.dart';
import 'support/test_identities.dart';

// 앱<->앱 1:1 push 전송을 두 registry가 인메모리 채널로 이어진 진짜 서버(loopback)로 끝까지 돌림:
// offer -> accept(토큰+attempt) -> POST(헤더 필수) -> AEAD
// 복호화/커밋 -> file_received ACK -> 보내는 쪽 complete

Future<void> _until(bool Function() done, {int ms = 5000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: ms));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory dir;
  late InMemoryStore sender;
  late InMemoryStore receiver;
  late LinkRegistry senderRegistry;
  late LinkRegistry receiverRegistry;
  late LocalServer server;
  late String senderConversation;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('intragram_push');
    sender = InMemoryStore();
    receiver = InMemoryStore();
    senderRegistry = LinkRegistry(
      store: sender,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'sender', platform: 't'),
    );
    final receiverIdentity = testIdentity(
      'b',
      alias: 'receiver',
      platform: 't',
    );
    receiverRegistry = LinkRegistry(
      store: receiver,
      crypto: CryptoEngine(),
      identity: receiverIdentity,
      chooseDirectory: (_) async => dir.path,
    );
    server = LocalServer(
      registry: receiverRegistry,
      identity: receiverIdentity,
      onInboundError: (error, _) => fail('inbound registration: $error'),
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final bound = (await server.start())!;
    receiverRegistry.localEndpoint = bound;
    final wire = StreamChannelController<dynamic>();
    await receiverRegistry.acceptInbound(
      wire.foreign,
      remoteHost: '127.0.0.1',
      remotePort: 12345,
    );
    senderConversation = await senderRegistry.debugAdoptDialledChannel(
      wire.local,
      remoteHost: '127.0.0.1',
      remotePort: bound.port,
    );
    await _until(() => sender.conversation(senderConversation)!.secure);
    addTearDown(() async {
      await server.stop();
      await senderRegistry.disposeAll();
      await receiverRegistry.disposeAll();
      sender.dispose();
      receiver.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  test(
    'a 1:1 file goes offer → accept → POST → ACK → complete on both ends',
    () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(300000, (i) => (i * 7) % 251),
      );
      await senderRegistry.offerInlineBytes(
        senderConversation,
        'data.bin',
        bytes,
      );
      final offered = sender.transfers.single;
      expect(offered.mode, FileTransferMode.push);
      await _until(() => receiver.transfer(offered.id) != null);
      final incoming = receiver.transfer(offered.id)!;
      expect(incoming.attemptId, offered.attemptId);
      expect(incoming.senderPeerId, testPeerId('a'));

      await receiverRegistry.acceptTransfer(offered.id);
      await _until(
        () =>
            receiver.transfer(offered.id)!.state == TransferState.complete &&
            sender.transfer(offered.id)!.state == TransferState.complete,
      );

      final done = receiver.transfer(offered.id)!;
      expect(done.state, TransferState.complete);
      expect(File(done.localPath!).readAsBytesSync(), bytes);
      expect(sender.transfer(offered.id)!.state, TransferState.complete);
      expect(
        dir.listSync().where((e) => e.path.endsWith('.part')),
        isEmpty,
        reason: 'the reserved partial was committed, none left behind',
      );
    },
  );

  test(
    'a rejected offer never moves bytes and frees the sender source',
    () async {
      await senderRegistry.offerInlineBytes(
        senderConversation,
        'no.bin',
        Uint8List(1000),
      );
      final offered = sender.transfers.single;
      await _until(() => receiver.transfer(offered.id) != null);
      await receiverRegistry.rejectTransfer(offered.id);
      await _until(
        () => sender.transfer(offered.id)!.state == TransferState.rejected,
      );
      expect(sender.transfer(offered.id)!.state, TransferState.rejected);
      expect(senderRegistry.outgoingSource(offered.id), isNull);
      expect(dir.listSync(), isEmpty);
    },
  );

  test('a picked (native) file pushes end to end and its source is released '
      'once, after the reader closed', () async {
    final fake = FakeFileSourceChannel(chunk: 100000, chunksPerFile: 3)
      ..install();
    await senderRegistry.offerStreamSources(
      senderConversation,
      await MobileFileSource.pick(),
    );
    final offered = sender.transfers.single;
    await _until(() => receiver.transfer(offered.id) != null);

    await receiverRegistry.acceptTransfer(offered.id);
    await _until(
      () =>
          receiver.transfer(offered.id)!.state == TransferState.complete &&
          sender.transfer(offered.id)!.state == TransferState.complete,
    );

    expect(sender.transfer(offered.id)!.state, TransferState.complete);
    expect(
      File(receiver.transfer(offered.id)!.localPath!).lengthSync(),
      fake.fileSize,
    );
    await _until(() => fake.count('release:') > 0);
    expect(fake.count('open:s1'), 1);
    expect(fake.count('close:'), 1);
    expect(fake.count('release:s1'), 1);
    expect(fake.indexOf('close:r1'), lessThan(fake.indexOf('release:s1')));
  });

  test('cancelling a push whose reader is stalled releases the source only '
      'after the reader closes', () async {
    final fake = FakeFileSourceChannel(chunk: 100000, chunksPerFile: 3)
      ..readGate = Completer<void>()
      ..install();
    await senderRegistry.offerStreamSources(
      senderConversation,
      await MobileFileSource.pick(),
    );
    final offered = sender.transfers.single;
    await _until(() => receiver.transfer(offered.id) != null);
    await receiverRegistry.acceptTransfer(offered.id);
    await _until(() => fake.count('read:') > 0);

    senderRegistry.cancelTransfer(offered.id);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fake.count('close:'), 0, reason: 'the read is still stalled');
    expect(fake.count('release'), 0, reason: 'the reader is not closed yet');

    fake.readGate!.complete();
    await _until(() => fake.count('release:') > 0);

    expect(fake.count('release:s1'), 1);
    expect(fake.indexOf('close:r1'), lessThan(fake.indexOf('release:s1')));
  });
}
