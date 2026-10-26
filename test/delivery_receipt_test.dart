import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/test_identities.dart';
import 'support/transfer_rig.dart';

// 수신 영수증이 진짜 암호 링크·HTTP를 지나 보내는 쪽 증적에 확정되는지: 서명·수신자 키·attempt·보낸 사람·
// 내가 내보낸 내용 해시가 다 맞아야 verified이고 하나라도 틀리면 rejected, 옛 attempt 영수증은 아예 안 붙음

final Uint8List _voice = Uint8List.fromList(
  List<int>.generate(65536, (i) => (i * 13) % 251),
)..setRange(0, 4, 'RIFF'.codeUnits);

Future<Map<String, dynamic>> _receipt(
  TransferRig rig,
  FileTransfer t, {
  String? commitment,
  String signer = 'b',
}) async => (await SignedAttestation.sign(
  testIdentity(signer),
  AttestationDraft(
    kind: AttestationKind.deliveryCommitted,
    subjectId: t.id,
    attemptId: t.attemptId,
    counterpartId: rig.registry.identity.peerId,
    counterpartKey: rig.registry.identity.publicKey,
    commitment: commitment ?? sha256B64(_voice),
    policy: t.voice ? 'delivery/voice-ram' : 'delivery/file-commit',
    outcome: 'committed',
  ),
)).toWire();

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('the sender confirms a receipt carried on file_received', () {
    Future<(TransferRig, FileTransfer)> pulled({bool room = false}) async {
      final rig = await TransferRig.create();
      final t = room
          ? await rig.offerRoomFile(await rig.formRoom(), _voice)
          : await rig.offerVoice(_voice);
      await rig.get(t.id, rig.headers(t));
      await pumpEventQueue(times: 30);
      return (rig, rig.store.transfer(t.id)!);
    }

    Iterable<EvidenceEntry> receipts(TransferRig rig, String id) => rig
        .store
        .evidence
        .forTransfer(id)
        .where((e) => e.attestation.kind == AttestationKind.deliveryCommitted);

    for (final room in [false, true]) {
      test(
        room ? 'room pull (offer digest)' : '1:1 voice (streamed digest)',
        () async {
          final (rig, t) = await pulled(room: room);
          await rig.remote.sendFileReceived(
            t.id,
            attemptId: t.attemptId!,
            receipt: await _receipt(rig, t),
          );
          await _until(() => receipts(rig, t.id).isNotEmpty);
          final entry = receipts(rig, t.id).single;
          expect(entry.status, EvidenceStatus.verified);
          expect(entry.attestation.signerPeerId, testPeerId('b'));
          expect(entry.attestation.commitment, sha256B64(_voice));
          expect(rig.store.transfer(t.id)!.state, TransferState.complete);
        },
      );
    }

    test(
      'a receipt over other bytes or from another key is rejected',
      () async {
        for (final (commitment, signer) in [
          (sha256B64([1, 2, 3]), 'b'),
          (null, 'c'),
        ]) {
          final (rig, t) = await pulled();
          await rig.remote.sendFileReceived(
            t.id,
            attemptId: t.attemptId!,
            receipt: await _receipt(
              rig,
              t,
              commitment: commitment,
              signer: signer,
            ),
          );
          await _until(() => receipts(rig, t.id).isNotEmpty);
          expect(receipts(rig, t.id).single.status, EvidenceStatus.rejected);
          // 영수증이 틀려도 완료는 예전처럼 ACK로 정함
          expect(rig.store.transfer(t.id)!.state, TransferState.complete);
        }
      },
    );

    test(
      'verification completing after secureWipe never revives evidence',
      () async {
        final (rig, t) = await pulled();
        final outgoing = rig.registry.debugOutgoing;
        outgoing.handleDeliveryReceipt(
          t.id,
          attemptId: t.attemptId!,
          actorKey: testPeerId('b'),
          receipt: await _receipt(rig, t),
        );
        outgoing.handleFileReceived(
          t.id,
          attemptId: t.attemptId!,
          actorKey: testPeerId('b'),
        );
        rig.store.secureWipe();
        await pumpEventQueue(times: 60);
        expect(rig.store.evidence.entries, isEmpty);
      },
    );

    test('a receipt for another attempt never attaches', () async {
      final (rig, t) = await pulled();
      final stale = {...await _receipt(rig, t), 'a': 'old-attempt'};
      await rig.remote.sendFileReceived(
        t.id,
        attemptId: 'old-attempt',
        receipt: stale,
      );
      await pumpEventQueue(times: 60);
      expect(receipts(rig, t.id), isEmpty);
      expect(rig.store.transfer(t.id)!.state, TransferState.transferring);
    });
  });

  test('a 1:1 push leaves the issued receipt on the receiver and the verified '
      'one on the sender, both over the same content hash', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_receipt');
    final sender = InMemoryStore();
    final receiver = InMemoryStore();
    final senderRegistry = LinkRegistry(
      store: sender,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'sender'),
    );
    final receiverIdentity = testIdentity('b', alias: 'receiver');
    final receiverRegistry = LinkRegistry(
      store: receiver,
      crypto: CryptoEngine(),
      identity: receiverIdentity,
      chooseDirectory: (_) async => dir.path,
    );
    final server = LocalServer(
      registry: receiverRegistry,
      identity: receiverIdentity,
      onInboundError: (error, _) => fail('inbound: $error'),
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final bound = (await server.start())!;
    addTearDown(() async {
      await server.stop();
      await senderRegistry.disposeAll();
      await receiverRegistry.disposeAll();
      sender.dispose();
      receiver.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    receiverRegistry.localEndpoint = bound;
    final wire = StreamChannelController<dynamic>();
    await receiverRegistry.acceptInbound(
      wire.foreign,
      remoteHost: '127.0.0.1',
      remotePort: 12345,
    );
    final conversation = await senderRegistry.debugAdoptDialledChannel(
      wire.local,
      remoteHost: '127.0.0.1',
      remotePort: bound.port,
    );
    await _until(() => sender.conversation(conversation)!.secure);

    final bytes = Uint8List.fromList(
      List<int>.generate(3 * 1024 * 1024 + 7, (i) => (i * 7) % 251),
    );
    await senderRegistry.offerInlineBytes(conversation, 'data.bin', bytes);
    final id = sender.transfers.single.id;
    await _until(() => receiver.transfer(id) != null);
    await receiverRegistry.acceptTransfer(id);
    await _until(() => sender.evidence.forTransfer(id).isNotEmpty);

    final issued = receiver.evidence.forTransfer(id).single;
    final confirmed = sender.evidence.forTransfer(id).single;
    expect(issued.status, EvidenceStatus.issued);
    expect(confirmed.status, EvidenceStatus.verified);
    expect(confirmed.attestation.eventId, issued.attestation.eventId);
    expect(confirmed.attestation.commitment, sha256B64(bytes));
    expect(confirmed.attestation.counterpartId, testPeerId('a'));
    expect(confirmed.attestation.counterpartKey, testIdentity('a').publicKey);
    expect(sender.transfer(id)!.state, TransferState.complete);
    expect(sender.transfer(id)!.contentCommitment, sha256B64(bytes));
    expect(receiver.transfer(id)!.contentCommitment, sha256B64(bytes));
  });
}
