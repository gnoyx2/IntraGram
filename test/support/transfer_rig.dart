import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'handshake_pair.dart' show conv;
import 'test_identities.dart';

// i번째 링크의 채널 한쪽을 감싸 결함을 주입하는 함수 (TransferRig.create)
typedef ChannelWrap =
    StreamChannel<dynamic> Function(int index, StreamChannel<dynamic> channel);

// 진짜 LocalServer와 진짜 암호화 링크(1:1)로 아웃고잉 전송을 끝까지 모는 rig.
// 호스트(보내는 쪽)는 registry/server, 받는 쪽은 인메모리 채널로 이어진
// remote 링크 (remote.sendFileReceived 같은 진짜 프레임으로
// ACK를 흉내냄). 서버는 loopback에 묶임 (테스트 전용 seam)
class TransferRig {
  TransferRig._({
    required this.store,
    required this.registry,
    required this.server,
    required this.bound,
    required this.remotes,
    required this.remoteStores,
    required this.serverErrors,
  });

  final InMemoryStore store;
  final LinkRegistry registry;
  final LocalServer server;
  final ({String host, int port}) bound;
  final List<PeerLink> remotes;
  final List<InMemoryStore> remoteStores;
  final List<Object> serverErrors;
  final HttpClient client = HttpClient();

  PeerLink get remote => remotes.first;

  // 호스트 쪽에서 i번째 remote 링크를 부르는 수신자 키 (= 그 remote의 peerId)
  static String keyOf(int i) => testPeerId(_tagOf(i));

  // i번째 remote의 고정 테스트 신원 태그 (b, c, d, ... 호스트는 a)
  static String _tagOf(int i) => String.fromCharCode(0x62 + i);

  static AppIdentity identityOf(int i) =>
      testIdentity(_tagOf(i), alias: 'peer$i', platform: 'test');

  // members가 2 이상이면 받는 쪽 링크를 그만큼 만들고 formRoom으로
  // 한 방에 묶을 수 있음 (각자 별개 host 문자열로 접속)
  // wrapHostChannel/wrapMemberChannel은 i번째 링크의 호스트/멤버 쪽 채널을 감싸 결함을 주입하게 하고,
  // configure는 멤버가 붙기 전에 레지스트리에 테스트 seam을 걸게 함
  static Future<TransferRig> create({
    Duration ackTimeout = const Duration(milliseconds: 300),
    int members = 1,
    ChannelWrap? wrapHostChannel,
    ChannelWrap? wrapMemberChannel,
    void Function(LinkRegistry registry)? configure,
  }) async {
    final store = InMemoryStore();
    final identity = testIdentity('a', alias: 'host', platform: 'test');
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity,
      ackTimeout: ackTimeout,
    );
    configure?.call(registry);
    final serverErrors = <Object>[];
    final server = LocalServer(
      registry: registry,
      identity: identity,
      onInboundError: (e, _) => serverErrors.add(e),
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final bound = (await runZonedGuarded<Future<({String host, int port})?>>(
      server.start,
      (e, _) => serverErrors.add(e),
    )!)!;
    registry.localEndpoint = bound;
    final remotes = <PeerLink>[];
    final remoteStores = <InMemoryStore>[];
    for (var i = 0; i < members; i++) {
      final wire = StreamChannelController<dynamic>();
      await registry.acceptInbound(
        wrapHostChannel?.call(i, wire.foreign) ?? wire.foreign,
        remoteHost: '192.168.1.${11 + i}',
        remotePort: 12345,
      );
      final remoteStore = InMemoryStore()
        ..upsertConversation(conv('remote$i', 'host'));
      remoteStores.add(remoteStore);
      remotes.add(
        PeerLink(
          conversationId: 'remote$i',
          channel: wrapMemberChannel?.call(i, wire.local) ?? wire.local,
          store: remoteStore,
          identity: identityOf(i),
          crypto: await CryptoEngine().createSession(),
          dialledByUs: true,
        ),
      );
    }
    final rig = TransferRig._(
      store: store,
      registry: registry,
      server: server,
      bound: bound,
      remotes: remotes,
      remoteStores: remoteStores,
      serverErrors: serverErrors,
    );
    addTearDown(rig.dispose);
    for (final remote in remotes) {
      await remote.start();
    }
    await pumpEventQueue(times: 100);
    for (final remote in remotes) {
      expect(remote.isSecure, isTrue);
    }
    return rig;
  }

  Future<void> dispose() async {
    client.close(force: true);
    await server.stop();
    await registry.disposeAll();
    for (final remote in remotes) {
      await remote.close();
    }
    store.dispose();
    for (final remoteStore in remoteStores) {
      remoteStore.dispose();
    }
  }

  // 받는 쪽 링크 전부를 호스트(이 기기)가 운영하는 한 그룹 방으로 묶고 방 대화 id를 돌려줌
  Future<String> formRoom() async {
    final first = store.conversations.firstWhere(
      (c) => c.peerHost == '192.168.1.11',
    );
    await registry.addPeersToRoom(first.id, [
      for (var i = 1; i < remotes.length; i++)
        PeerDevice(
          peerId: keyOf(i),
          alias: 'peer$i',
          platform: 'test',
          host: '192.168.1.${11 + i}',
          port: 7890,
          seenAt: DateTime(2026),
        ),
    ]);
    await pumpEventQueue(times: 100);
    return registry.appRoomId!;
  }

  Future<FileTransfer> offerRoomFile(String roomId, Uint8List bytes) async {
    await registry.offerInlineBytes(roomId, 'room.bin', bytes);
    return store.transfers.single;
  }

  // 64KiB 음성 메시지(RIFF 머리)를 offer하고 그 전송 레코드를 돌려줌
  Future<FileTransfer> offerVoice([Uint8List? bytes]) async {
    final data =
        bytes ??
        (Uint8List.fromList(List<int>.generate(65536, (i) => i % 251))
          ..setRange(0, 4, 'RIFF'.codeUnits));
    await registry.offerInlineBytes(
      store.conversations.first.id,
      'voice-note.wav',
      data,
      mime: 'audio/wav',
      voice: true,
    );
    return store.transfers.single;
  }

  String tokenOf(FileTransfer t) =>
      registry.outgoingSource(t.id)!.downloadToken!;

  // GET 헤더 묶음: 기본은 전부 정상값이고 overrides로 바꾸거나 null로 뺌
  Map<String, String> headers(
    FileTransfer t, {
    Map<String, String?> overrides = const {},
  }) {
    final h = <String, String>{
      'x-transfer-token': tokenOf(t),
      'x-transfer-attempt': store.transfer(t.id)!.attemptId!,
      'x-file-size': '${t.totalBytes}',
    };
    overrides.forEach((k, v) => v == null ? h.remove(k) : h[k] = v);
    return h;
  }

  Future<({int status, int? length, List<int> body})> get(
    String transferId,
    Map<String, String> headers,
  ) async {
    final request = await client.getUrl(
      Uri.parse('http://${bound.host}:${bound.port}/api/download/$transferId'),
    );
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = <int>[];
    try {
      await for (final chunk in response) {
        body.addAll(chunk);
      }
    } on HttpException {
      // 끊긴 응답: 받은 만큼만 돌려줌
    }
    return (
      status: response.statusCode,
      length: response.contentLength < 0 ? null : response.contentLength,
      body: body,
    );
  }
}
