import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/test_identities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file sender metadata rejects small-order Ed25519 keys', () {
    final offer = InnerFrame.fileOffer(
      id: 'file',
      attempt: 'attempt',
      mode: 'push',
      name: 'file.bin',
      size: 3,
      enc: true,
    );
    for (final y in [0, 1]) {
      final key = Uint8List(32)..[0] = y;
      expect(
        InboundInner.fromJson({...offer, 'sk': base64.encode(key)}),
        isA<MalformedInner>(),
      );
    }
    expect(
      InboundInner.fromJson({
        ...offer,
        'sk': base64.encode(testIdentity('a').publicKey!),
      }),
      isA<FileOfferInner>(),
    );
  });

  test(
    'a weak sender key cannot be stored through encrypted offer dispatch',
    () async {
      final pair = await connectedPair();
      addTearDown(() async {
        await pair.linkA.close();
        await pair.linkB.close();
        pair.storeA.dispose();
        pair.storeB.dispose();
      });
      await pair.linkA.sendRawInner(
        InnerFrame.fileOffer(
          id: 'weak',
          attempt: 'attempt',
          mode: 'push',
          name: 'file.bin',
          size: 3,
          enc: true,
          senderPubKey: base64.encode(Uint8List(32)..[0] = 1),
        ),
      );
      await pumpEventQueue(times: 60);
      expect(pair.storeB.transfer('weak'), isNull);
    },
  );

  test(
    'a legacy stored weak sender key cannot receive a signed receipt',
    () async {
      final pair = await connectedPair();
      final directory = Directory.systemTemp.createTempSync('weak_sender_');
      final incoming = IncomingTransfers(
        store: pair.storeB,
        linkFor: (_) => pair.linkB,
        gate: TransferConcurrencyGate(),
        chooseDirectory: (_) async => directory.path,
      );
      addTearDown(() async {
        await incoming.clear();
        await pair.linkA.close();
        await pair.linkB.close();
        pair.storeA.dispose();
        pair.storeB.dispose();
        await pair.storeB.drainDisposals();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final key = Uint8List(32)..[0] = 1;
      pair.storeB.upsertTransfer(
        FileTransfer(
          id: 'weak',
          conversationId: 'cB',
          direction: TransferDirection.incoming,
          fileName: 'received.bin',
          totalBytes: 3,
          attemptId: 'attempt',
          senderPeerId: peerIdOfKey(key),
          senderPubKey: base64.encode(key),
        ),
      );
      await incoming.accept('weak');
      await incoming.receive(
        transferId: 'weak',
        attemptId: 'attempt',
        token: incoming.debugPushTokenFor('weak')!,
        body: Stream<List<int>>.value(const [1, 2, 3]),
        headerDeclaredSize: 3,
      );
      await pumpEventQueue(times: 60);
      expect(pair.storeB.transfer('weak')!.state, TransferState.complete);
      expect(pair.storeB.evidence.entries, isEmpty);
    },
  );
}
