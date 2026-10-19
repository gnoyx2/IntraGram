import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';

import 'support/mobile_source_rig.dart';

// 방 전송은 첫 제안 전에 원본을 한 번 읽어 SHA-256을 잼. 그 읽기도 reader라서, 재는 도중 취소·소각하면
// 읽기를 끊고 닫힌 뒤에만 native 원본을 놓음 (읽는 중에 놓지 않음)
void main() {
  late MobileSourceRig m;
  setUp(() async => m = await MobileSourceRig.create());

  // 읽기를 멈춰 둔 채 방에 제안: 해시 읽기(r1)에서 멈춤
  Future<String> offerWhileHashing() async {
    m.fake.readGate = Completer<void>();
    m.fake.pickCount = 1;
    final picked = await MobileFileSource.pick();
    unawaited(m.rig.registry.offerStreamSources(m.roomId, picked));
    await settle();
    expect(m.fake.count('read:r1'), 1, reason: 'the digest read is stalled');
    return m.rig.store.transfers.first.id;
  }

  test('cancelling while the sender hashes releases only after that read '
      'closes, and offers nothing', () async {
    final id = await offerWhileHashing();

    m.rig.registry.cancelTransfer(id);
    await settle();
    expect(m.fake.count('release'), 0, reason: 'the digest read is open');

    m.fake.readGate!.complete();
    await settle();
    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.indexOf('close:r1'), lessThan(m.fake.indexOf('release:s1')));
    expect(m.fake.count('read:r1'), lessThan(3), reason: 'stopped early');
    for (var i = 0; i < 2; i++) {
      expect(m.rig.remoteStores[i].transfer(id), isNull, reason: 'member $i');
    }
  });

  test('a burn while the sender hashes waits for that read too', () async {
    final id = await offerWhileHashing();

    var discarded = false;
    final discarding = m.out.discard(id).then((_) => discarded = true);
    await settle();
    expect(discarded, isFalse);
    expect(m.fake.count('release'), 0);

    m.fake.readGate!.complete();
    await discarding;
    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.indexOf('close:r1'), lessThan(m.fake.indexOf('release:s1')));
  });
}
