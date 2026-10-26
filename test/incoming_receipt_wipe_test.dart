import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/in_memory_store_fixtures.dart';
import 'support/test_identities.dart';

// 커밋 직후 삭제가 끼어든 뒤에도 수신 콜스택은 옛 transfer를 쥐고 있음.
class _WipeAtCommitStore extends InMemoryStore {
  bool wiped = false;

  @override
  void updateTransfer(String id, FileTransfer Function(FileTransfer) update) {
    super.updateTransfer(id, update);
    if (transfer(id)?.state == TransferState.complete) {
      wiped = true;
      secureWipe();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a commit racing secureWipe cannot issue a receipt afterwards',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'intragram_receipt_wipe_',
      );
      final store = _WipeAtCommitStore()..upsertConversation(conversation('c'));
      store.evidence.bindSigner(testIdentity('b'));
      final wire = StreamChannelController<dynamic>();
      final link = PeerLink(
        conversationId: 'c',
        channel: wire.local,
        store: store,
        identity: testIdentity('b'),
        crypto: await CryptoEngine().createSession(),
      );
      final incoming = IncomingTransfers(
        store: store,
        linkFor: (_) => link,
        gate: TransferConcurrencyGate(),
        chooseDirectory: (_) async => dir.path,
      );
      addTearDown(() async {
        await incoming.clear();
        await link.close();
        store.dispose();
        await store.drainDisposals();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      store.upsertTransfer(
        FileTransfer(
          id: 't',
          conversationId: 'c',
          direction: TransferDirection.incoming,
          fileName: 'received.bin',
          totalBytes: 3,
          attemptId: 'a',
          senderPeerId: testPeerId('a'),
          senderPubKey: base64.encode(testIdentity('a').publicKey!),
        ),
      );
      await incoming.accept('t');
      await incoming.receive(
        transferId: 't',
        attemptId: 'a',
        token: incoming.debugPushTokenFor('t')!,
        body: Stream<List<int>>.value(const [1, 2, 3]),
        headerDeclaredSize: 3,
      );
      await pumpEventQueue(times: 60);

      expect(store.wiped, isTrue);
      expect(store.transfers, isEmpty);
      expect(store.evidence.entries, isEmpty);
    },
  );
}
