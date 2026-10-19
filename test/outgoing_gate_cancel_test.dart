import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'support/transfer_rig.dart';

void main() {
  test('cancel while GET waits for gate never revives the offer', () async {
    final rig = await TransferRig.create();
    final transfer = await rig.offerVoice();
    final outgoing = rig.registry.debugOutgoing;
    for (var i = 0; i < kMaxConcurrentTransfers; i++) {
      await outgoing.gate.acquire();
    }
    final recipient = outgoing.debugRecipients(transfer.id).single;
    final pending = outgoing.openDownload(
      transferId: transfer.id,
      attemptId: recipient.attemptId,
      token: recipient.pullToken!,
      declaredSize: transfer.totalBytes,
    );
    await pumpEventQueue(times: 60);
    rig.registry.cancelTransfer(transfer.id);
    await expectLater(pending, throwsA(isA<TransferCancelledException>()));
    expect(rig.store.transfer(transfer.id)!.state, TransferState.cancelled);
    for (var i = 0; i < kMaxConcurrentTransfers; i++) {
      outgoing.gate.release();
    }
  });
}
