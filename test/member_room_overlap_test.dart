import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/member_room_rig.dart';

// 같은 멤버(peerId)의 링크가 잠시 둘인 구간(재접속 직후 옛 링크가 아직 안 닫힘)과 여러 링크가
// 한 틱에 같이 끊기는 경우: 방 상태·경로·전송이 링크가 아니라 멤버 기준으로 맞아야 함
void main() {
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);

  Future<FileTransfer> hostOffer(MemberRoomRig r) async {
    final registry = r.rig.registry;
    // 멤버의 엄격 파서는 사설 주소가 아닌 `sh`(rig 서버는 loopback)를 거부함
    registry.localEndpoint = (host: '192.168.1.10', port: 7890);
    await registry.offerInlineBytes(
      registry.appRoomId!,
      'host.bin',
      Uint8List(8),
    );
    await pumpEventQueue(times: 80);
    return r.rig.store.transfers.single;
  }

  test('several links closing in the same tick spare other members', () async {
    final r = await MemberRoomRig.create();
    final t = await hostOffer(r);
    final third = r.copyAt(2, t.id)!;

    unawaited(r.rig.remotes[0].close());
    unawaited(r.rig.remotes[1].close());
    await pumpEventQueue(times: 200);

    final registry = r.rig.registry;
    expect(
      registry.outgoingSource(t.id),
      isNotNull,
      reason: 'the transfer is not discarded for the member that stayed',
    );
    final download = await registry.openDownload(
      transferId: t.id,
      attemptId: third.attemptId!,
      token: third.pullToken!,
      declaredSize: t.totalBytes,
    );
    expect(download, isNotNull, reason: 'the remaining member can still pull');
    await download!.body.drain<void>();
  });

  group(
    'a member with two live links (reconnect before the old one closed)',
    () {
      late MemberRoomRig r;
      setUp(() async => r = await MemberRoomRig.create());

      test('is counted once in the room', () async {
        await r.reconnect(1, host: '192.168.1.99');
        final room = r.rig.store.conversation(r.rig.registry.appRoomId!)!;
        expect(room.memberCount, 4, reason: 'host + three members');
      });

      test('gets the host offer on its newest link only', () async {
        final again = await r.reconnect(1, host: '192.168.1.99');
        final t = await hostOffer(r);
        expect(r.copyAt(1, t.id), isNull, reason: 'the old link is not used');
        expect(again.store.transfer(t.id)?.attemptId, isNotNull);
        expect(r.copyAt(2, t.id)?.attemptId, isNotNull);
      });

      test('keeps its routes when the old link closes afterwards', () async {
        final t = await r.offer();
        expect(r.routeCount, 2);
        final again = await r.reconnect(1, host: '192.168.1.99');
        final attempt = r.copyAt(1, t.id)!.attemptId!;

        await r.rig.remotes[1].close(); // 옛 M2 링크가 뒤늦게 닫힘
        await pumpEventQueue(times: 100);

        expect(r.routeCount, 2, reason: 'M2 is still in the room');
        expect(r.phases(t.id), {
          r.hostId: 'offered',
          m2: 'offered',
          m3: 'offered',
        });
        final room = r.rig.store.conversation(r.rig.registry.appRoomId!)!;
        expect(room.members[m2]?.online, isTrue);
        expect(
          r.rig.store
              .messages(room.id)
              .where((m) => m.systemEvent?.kind == SystemEventKind.memberLeft),
          isEmpty,
          reason: 'nobody left',
        );

        await again.link.sendFileAccept(
          t.id,
          attemptId: attempt,
          pushToken: 'x',
        );
        await pumpEventQueue(times: 60);
        expect(r.senderEvents, ['accept:c:$attempt']);
      });

      // 옛 링크는 isClosed가 바로 서지만 소켓 종료(최대 2초)가 끝나야 정리(_onLinkClosed)가 돎. 그 구간에도
      // 새 링크의 accept/ACK는 경로를 물려받아 발신자한테 가야 함: 정리가 끝난 뒤에만 되면 안 됨
      test(
        'hands the routes to the new link before the old one finished closing',
        () async {
          final t = await r.offer();
          final attempt = r.copyAt(1, t.id)!.attemptId!;
          final wire = r.faults.hostChannels[1];
          final gate = wire.closeGate = Completer<void>();

          final again = await r.reconnect(1, host: '192.168.1.99');
          expect(
            wire.closeStarted,
            isTrue,
            reason: 'the old link is shutting down',
          );
          expect(
            gate.isCompleted,
            isFalse,
            reason: 'and its socket close is stuck',
          );

          await again.link.sendFileAccept(
            t.id,
            attemptId: attempt,
            pushToken: 'x',
          );
          await pumpEventQueue(times: 60);
          await again.link.sendFileReceived(t.id, attemptId: attempt);
          await pumpEventQueue(times: 60);

          expect(
            r.senderEvents,
            ['accept:c:$attempt', 'received:c:$attempt'],
            reason: 'delivered while the old close future is still pending',
          );
          expect(gate.isCompleted, isFalse);
          expect(r.routeCount, 1, reason: 'the ACK ended only the M2 route');

          // 뒤늦게 옛 링크의 정리가 돌아도 새 경로·멤버·다른 수신자를 안 건드림(멱등)
          gate.complete();
          await pumpEventQueue(times: 100);
          expect(
            r.routeCount,
            1,
            reason: 'the M3 route survives the late cleanup',
          );
          expect(r.phases(t.id)[m3], 'offered');
          final room = r.rig.store.conversation(r.rig.registry.appRoomId!)!;
          expect(room.members[m2]?.online, isTrue);
          expect(
            r.rig.store
                .messages(room.id)
                .where(
                  (m) => m.systemEvent?.kind == SystemEventKind.memberLeft,
                ),
            isEmpty,
            reason: 'nobody left',
          );
          await r.rig.remotes[2].sendFileAccept(
            t.id,
            attemptId: r.copyAt(2, t.id)!.attemptId!,
            pushToken: 'y',
          );
          await pumpEventQueue(times: 60);
          expect(r.senderEvents.last, startsWith('accept:d:'));
        },
      );

      test(
        'a late failed offer removes the route after target handover',
        () async {
          await r.offer(); // 기존 M1→M2/M3 경로 둘은 보존돼야 함
          final registry = r.rig.registry;
          final wire = StreamChannelController<dynamic>();
          final id = await registry.debugAdoptDialledChannel(
            wire.foreign,
            remoteHost: '192.168.1.99',
            remotePort: 12345,
          );
          final store = InMemoryStore()
            ..upsertConversation(conv('again', 'host'));
          addTearDown(store.dispose);
          final duplicate = PeerLink(
            conversationId: 'again',
            channel: wire.local,
            store: store,
            identity: r.rig.remotes[1].identity,
            crypto: await CryptoEngine().createSession(),
          );
          addTearDown(duplicate.close);
          await duplicate.start();
          await r.until(() => registry.linkFor(id)?.isSecure ?? false);

          // 옛 링크의 offer write 바로 앞에서 새 링크를 방으로 승격해 경로를 인계하고,
          // 그 옛 write만 실패시킴. 비동기 결과가 돌아올 때 경로 객체가 바뀌면 실패한
          // offer의 경로가 새 링크에 고아로 남았음
          var switched = false;
          r.faults.hostChannels[1].beforeAdd = () {
            if (switched) return;
            switched = true;
            unawaited(
              registry.inviteToRoom(
                PeerDevice(
                  peerId: m2,
                  alias: 'peer1',
                  platform: 'test',
                  host: '192.168.1.99',
                  port: 12345,
                  seenAt: DateTime.now(),
                ),
              ),
            );
            throw StateError('old target write failed after handover');
          };
          await r.rawOffer(id: 'raced', attempt: 'a-raced', to: m2);
          await r.until(() => r.senderEvents.isNotEmpty);

          expect(switched, isTrue);
          expect(r.senderEvents, ['unavailable:c:a-raced']);
          expect(r.routeCount, 2, reason: 'the failed offer left no new route');
          expect(
            registry.linkFor(id),
            isNull,
            reason: 'the link moved into the room',
          );
        },
      );
    },
  );
}
