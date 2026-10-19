import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/models.dart';

import 'support/transfer_rig.dart';

void main() {
  test('room member gives host and peer independent pull offers', () async {
    final rig = await TransferRig.create(members: 2);
    await rig.formRoom();
    final senderStore = rig.remoteStores[0];
    final room = senderStore.conversation('remote0')!;
    expect(room.isRoom, isTrue);

    final sender = OutgoingTransfers(
      store: senderStore,
      identity: rig.remotes[0].identity,
      linkFor: (_) => rig.remotes[0],
      linksForTransfer: (_) => [rig.remotes[0]],
      gate: TransferConcurrencyGate(),
      localEndpoint: () => (host: '192.168.1.11', port: 7890),
    );
    addTearDown(sender.clear);
    await sender.offerInlineBytes('remote0', 'group.bin', Uint8List(8));
    final transfer = senderStore.transfers.singleWhere(
      (t) => t.direction == TransferDirection.outgoing,
    );
    final recipients = sender.debugRecipients(transfer.id);

    expect(recipients.map((r) => r.key).toSet(), {
      rig.registry.identity.peerId,
      TransferRig.keyOf(1),
    });
    expect(recipients.map((r) => r.attemptId).toSet(), hasLength(2));
    expect(recipients.map((r) => r.pullToken).toSet(), hasLength(2));
    await pumpEventQueue(times: 60);
    final hostOffer = rig.store.transfer(transfer.id)!;
    final peerOffer = rig.remoteStores[1].transfer(transfer.id)!;
    expect(
      hostOffer.attemptId,
      recipients
          .firstWhere((r) => r.key == rig.registry.identity.peerId)
          .attemptId,
    );
    expect(
      peerOffer.attemptId,
      recipients.firstWhere((r) => r.key == TransferRig.keyOf(1)).attemptId,
    );
    expect(hostOffer.pullToken, isNot(peerOffer.pullToken));
    final hostLink = rig.registry.linkForIncomingTransfer(hostOffer);
    expect(hostLink, isNotNull);
    expect(hostLink!.remotePeerId, TransferRig.keyOf(0));
    await expectLater(
      sender.openDownload(
        transferId: transfer.id,
        attemptId: hostOffer.attemptId!,
        token: peerOffer.pullToken!,
        declaredSize: transfer.totalBytes,
      ),
      throwsA(isA<SecurityException>()),
      reason: 'one recipient cannot spend another recipient token',
    );

    rig.remotes[0].onFileAccepted = (id, attempt, token, actor) {
      sender.handleAccepted(
        id,
        attemptId: attempt,
        pushToken: token,
        actorKey: actor,
      );
    };
    rig.remotes[0].onFileReceived = (id, attempt, actor) {
      sender.handleFileReceived(id, attemptId: attempt, actorKey: actor);
    };
    await rig.remotes[1].sendFileAccept(
      transfer.id,
      attemptId: peerOffer.attemptId!,
      pushToken: 'peer-accept',
    );
    await pumpEventQueue(times: 40);
    expect(
      sender
          .debugRecipients(transfer.id)
          .firstWhere((r) => r.key == TransferRig.keyOf(1))
          .phase,
      'accepted',
    );

    final peerDownload = (await sender.openDownload(
      transferId: transfer.id,
      attemptId: peerOffer.attemptId!,
      token: peerOffer.pullToken!,
      declaredSize: transfer.totalBytes,
    ))!;
    await peerDownload.body.drain<void>();
    await rig.remotes[1].sendFileReceived(
      transfer.id,
      attemptId: peerOffer.attemptId!,
    );
    await pumpEventQueue(times: 40);
    final phases = {
      for (final r in sender.debugRecipients(transfer.id)) r.key: r.phase,
    };
    expect(phases[TransferRig.keyOf(1)], 'complete');
    expect(phases[rig.registry.identity.peerId], 'offered');

    await hostLink.sendFileAccept(
      transfer.id,
      attemptId: hostOffer.attemptId!,
      pushToken: 'host-accept',
    );
    await pumpEventQueue(times: 40);
    final hostDownload = (await sender.openDownload(
      transferId: transfer.id,
      attemptId: hostOffer.attemptId!,
      token: hostOffer.pullToken!,
      declaredSize: transfer.totalBytes,
    ))!;
    await hostDownload.body.drain<void>();
    await hostLink.sendFileReceived(
      transfer.id,
      attemptId: hostOffer.attemptId!,
    );
    await pumpEventQueue(times: 40);
    expect(senderStore.transfer(transfer.id)!.state, TransferState.complete);
  });
}
