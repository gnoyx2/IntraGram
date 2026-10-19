import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'faulty_channels.dart';
import 'handshake_pair.dart' show conv;
import 'transfer_rig.dart';

// 호스트(진짜 LinkRegistry)가 운영하는 앱 그룹 방 + 멤버 셋. 첫 멤버(M1,
// remotes[0])는 진짜 OutgoingTransfers로 파일을 내고
// 나머지(M2/M3)는 진짜 링크의 프레임(accept/received/retry...)으로
// 수신자를 흉내냄. 호스트의 방 인가/라우팅은 진짜 코드를 그대로 탐
// peerId 첫 글자: 호스트 a, M1 b, M2 c, M3 d
class MemberRoomRig {
  MemberRoomRig._(this.rig, this.sender, this.faults);

  final TransferRig rig;
  final OutgoingTransfers sender;

  // 링크마다 감싼 채널과 만들어진 세션 (결함 주입용 RigFaults)
  final RigFaults faults;

  // M1 링크가 받은 파일 제어 프레임("종류:발신자 첫 글자:attempt"): "이 프레임은
  // 발신자에게 안 닿음"을 검사할 때 씀 (멤버 i가 받은 건 memberEvents)
  final List<String> senderEvents = <String>[];
  final Map<int, List<String>> memberEvents = <int, List<String>>{};

  // M1 쪽에서 본 방 대화 id
  static const String roomId = 'remote0';

  static Future<MemberRoomRig> create({
    int members = 3,
    bool serverUp = true,
  }) async {
    final faults = RigFaults();
    final rig = await TransferRig.create(
      members: members,
      wrapHostChannel: faults.wrapHost,
      wrapMemberChannel: faults.wrapMember,
      configure: faults.sessions.attach,
    );
    await rig.formRoom();
    final sender = OutgoingTransfers(
      store: rig.remoteStores[0],
      identity: rig.remotes[0].identity,
      linkFor: (_) => rig.remotes[0],
      linksForTransfer: (_) => [rig.remotes[0]],
      gate: TransferConcurrencyGate(),
      localEndpoint: () => serverUp ? (host: '192.168.1.11', port: 7890) : null,
    );
    addTearDown(sender.clear);
    return MemberRoomRig._(rig, sender, faults).._wire();
  }

  void _wire() {
    final link = rig.remotes[0];
    String tag(String kind, String actor, String at) => '$kind:${actor[0]}:$at';
    link.onFileAccepted = (id, at, token, actor) {
      senderEvents.add(tag('accept', actor, at));
      sender.handleAccepted(
        id,
        attemptId: at,
        pushToken: token,
        actorKey: actor,
      );
    };
    link.onFileRejected = (id, at, actor) {
      senderEvents.add(tag('reject', actor, at));
      sender.handleRejected(id, attemptId: at, actorKey: actor);
    };
    link.onFileCancelled = (id, at, actor) {
      senderEvents.add(tag('cancel', actor, at));
      sender.handleCancelledByPeer(id, attemptId: at, actorKey: actor);
    };
    link.onFileReceived = (id, at, actor) {
      senderEvents.add(tag('received', actor, at));
      sender.handleFileReceived(id, attemptId: at, actorKey: actor);
    };
    link.onFileRetryRequested = (id, at, actor) {
      senderEvents.add(tag('retry', actor, at));
      unawaited(
        sender.handleRetryRequested(id, attemptId: at, actorKey: actor),
      );
    };
    link.onFileUnavailable = (id, at, target) {
      senderEvents.add(tag('unavailable', target, at));
      sender.handleUnavailable(id, attemptId: at, targetKey: target);
    };
    link.onRoomRoster = (peers) => sender.handleRoomRoster(roomId, peers);
    for (var i = 1; i < rig.remotes.length; i++) {
      final events = memberEvents.putIfAbsent(i, () => <String>[]);
      rig.remotes[i].onFileCancelled = (id, at, actor) =>
          events.add(tag('cancel', actor, at));
      rig.remotes[i].onFileUnavailable = (id, at, target) =>
          events.add(tag('unavailable', target, at));
    }
  }

  // 호스트가 i번째 멤버와 쥐고 있는 링크(열려 있는 것 중 가장 최근): 닫기
  // 시작하면 목록에서 빠지니 닫히는 중인 링크를 다루려면 그 전에 잡아 둘 것
  PeerLink hostLinkOf(int i) => rig.registry
      .linksForTransfer(rig.registry.appRoomId!)
      .lastWhere((link) => link.remotePeerId == memberId(i));

  static String memberId(int i) => TransferRig.keyOf(i);
  String get hostId => rig.registry.identity.peerId;
  InMemoryStore get senderStore => rig.remoteStores[0];
  int get routeCount => rig.registry.debugRoomFileRouteCount;

  FileTransfer? hostCopy(String id) => rig.store.transfer(id);
  FileTransfer? copyAt(int i, String id) => rig.remoteStores[i].transfer(id);

  // 발신자가 본 수신자별 단계 (키는 수신자 peerId)
  Map<String, String> phases(String id) => {
    for (final r in sender.debugRecipients(id)) r.key: r.phase,
  };

  Future<FileTransfer> offer([Uint8List? bytes]) async {
    await sender.offerInlineBytes(roomId, 'group.bin', bytes ?? Uint8List(8));
    await pumpEventQueue(times: 80);
    return senderStore.transfers.singleWhere(
      (t) => t.direction == TransferDirection.outgoing,
    );
  }

  // sender 없이 link번 멤버 링크로 offer 프레임 하나를 직접 냄: 그 링크
  // 쪽 스토어엔 그 id의 아웃고잉 레코드를 대신 세워 둬서(제어 프레임 인가가 요구함)
  // 돌아오는 accept/ACK가 이벤트 기록에 남게 함
  Future<bool> rawOffer({
    required String id,
    required String attempt,
    String? to,
    String name = 'group.bin',
    String host = '192.168.1.11',
    String? thumb,
    int link = 0,
  }) {
    final store = rig.remoteStores[link];
    if (store.transfer(id) == null) {
      store.upsertTransfer(
        FileTransfer(
          id: id,
          conversationId: 'remote$link',
          direction: TransferDirection.outgoing,
          fileName: name,
          totalBytes: 8,
          attemptId: attempt,
          mode: FileTransferMode.pull,
        ),
      );
    }
    return rig.remotes[link].sendFileOffer(
      transferId: id,
      attemptId: attempt,
      mode: 'pull',
      name: name,
      size: 8,
      srcHost: host,
      srcPort: 7890,
      thumb: thumb,
      pullToken: 'tok-$attempt',
      to: to,
    );
  }

  Future<void> receiveAsMember(int i, String id) async {
    final offer = copyAt(i, id)!;
    await rig.remotes[i].sendFileAccept(
      id,
      attemptId: offer.attemptId!,
      pushToken: 'accept-$i',
    );
    await pumpEventQueue(times: 40);
    await _pullAndAck(rig.remotes[i], offer);
  }

  Future<void> receiveAsHost(String id) async {
    final offer = hostCopy(id)!;
    final link = rig.registry.linkForIncomingTransfer(offer)!;
    await link.sendFileAccept(
      id,
      attemptId: offer.attemptId!,
      pushToken: 'accept-host',
    );
    await pumpEventQueue(times: 40);
    await _pullAndAck(link, offer);
  }

  Future<void> _pullAndAck(PeerLink link, FileTransfer offer) async {
    final download = (await sender.openDownload(
      transferId: offer.id,
      attemptId: offer.attemptId!,
      token: offer.pullToken!,
      declaredSize: offer.totalBytes,
    ))!;
    await download.body.drain<void>();
    await link.sendFileReceived(offer.id, attemptId: offer.attemptId!);
    await pumpEventQueue(times: 40);
  }

  // 조건이 참이 될 때까지(최대 ~4000 이벤트 턴) 이벤트 큐를 돌림:
  // 큰 프레임처럼 암호화에 시간이 걸리는 경로에서 고정 횟수 펌프 대신
  // 씀
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await pumpEventQueue(times: 20);
    }
  }

  // 멤버 i로 방에 다시 붙는 새 링크(같은 peerId, 새 소켓)와 그 스토어를 만듦
  Future<({PeerLink link, InMemoryStore store})> reconnect(
    int i, {
    String? host,
  }) async {
    final wire = StreamChannelController<dynamic>();
    await rig.registry.acceptInbound(
      wire.foreign,
      remoteHost: host ?? '192.168.1.${11 + i}',
      remotePort: 12345,
    );
    final store = InMemoryStore()..upsertConversation(conv('again$i', 'host'));
    addTearDown(store.dispose);
    final link = PeerLink(
      conversationId: 'again$i',
      channel: wire.local,
      store: store,
      identity: TransferRig.identityOf(i),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    );
    addTearDown(link.close);
    await link.start();
    await pumpEventQueue(times: 100);
    return (link: link, store: store);
  }
}
