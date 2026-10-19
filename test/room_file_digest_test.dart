import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/transfer_rig.dart';

// 방 파일은 바이트가 평문으로 가서 LAN 중간자가 같은 길이로 바꿔치기할 수 있음: 인증된 링크로 가는
// offer에 내용의 SHA-256을 싣고, 받는 쪽은 받은 바이트가 다르면 지우고 실패로 둠
void main() {
  String sha(List<int> bytes) =>
      base64.encode(const DartSha256().hashSync(bytes).bytes);
  final content = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
  final swapped = Uint8List.fromList(content.reversed.toList());

  test('the offer carries the digest and the parser checks its shape', () {
    final frame = InnerFrame.fileOffer(
      id: 'f1',
      attempt: 'a1',
      mode: 'pull',
      name: 'x.bin',
      size: content.length,
      srcHost: '192.168.1.9',
      srcPort: 7890,
      token: 'tok',
      digest: sha(content),
    );
    expect(
      (InboundInner.fromJson(frame) as FileOfferInner).digest,
      sha(content),
    );
    for (final bad in <Object>['short', base64.encode(Uint8List(31)), 42]) {
      expect(
        InboundInner.fromJson({...frame, 'dg': bad}),
        isA<MalformedInner>(),
        reason: '$bad',
      );
    }
  });

  test('a room offer reaches the host and the other member with the '
      'content digest', () async {
    final rig = await TransferRig.create(members: 2);
    await rig.formRoom();
    final sender = OutgoingTransfers(
      store: rig.remoteStores[0],
      identity: rig.remotes[0].identity,
      linkFor: (_) => rig.remotes[0],
      linksForTransfer: (_) => [rig.remotes[0]],
      gate: TransferConcurrencyGate(),
      localEndpoint: () => (host: '192.168.1.11', port: 7890),
    );
    addTearDown(sender.clear);

    await sender.offerInlineBytes('remote0', 'group.bin', content);
    await pumpEventQueue(times: 60);

    final id = rig.remoteStores[0].transfers.single.id;
    expect(rig.store.transfer(id)!.digest, sha(content));
    expect(rig.remoteStores[1].transfer(id)!.digest, sha(content));
  });

  group('a pull checks the bytes against the offered digest', () {
    late HttpServer server;
    var served = <int>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.forEach((request) async {
          request.response.add(served);
          await request.response.close();
        }),
      );
    });
    tearDown(() => server.close(force: true));

    test('a swapped file of the same length is deleted', () async {
      final dir = Directory.systemTemp.createTempSync('intragram_digest');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}x.part';
      Future<int> pull() => FileStreamer.download(
        host: server.address.address,
        port: server.port,
        transferId: 't1',
        attemptId: 'a1',
        authToken: 'tok',
        destinationPath: path,
        declaredSize: content.length,
        sha256: sha(content),
      );

      served = content;
      expect(await pull(), content.length);

      served = swapped;
      await expectLater(pull(), throwsA(isA<ContentMismatchException>()));
      expect(File(path).existsSync(), isFalse);
      expect(
        classifyTransferError(const ContentMismatchException()),
        'tampered',
      );
    });

    test('a swapped voice note never reaches the player', () async {
      served = swapped;
      await expectLater(
        FileStreamer.downloadToMemory(
          host: server.address.address,
          port: server.port,
          transferId: 't1',
          attemptId: 'a1',
          authToken: 'tok',
          declaredSize: content.length,
          sha256: sha(content),
        ),
        throwsA(isA<ContentMismatchException>()),
      );
    });
  });
  // 바꿔치기로 실패한 전송은 같은 발신자가 다시 제안해도 묻지 않고 받지 않음: 방의 다른 멤버가 큰 파일을 거듭
  // 재제안해 받는 쪽이 계속 내려받게 만들 수 있음. 네트워크 실패는 전처럼 이어받음
  test('a re-offer after a tampered transfer asks again', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);
    final autoAccepted = <String>[];
    p.linkB.onAutoAcceptOffer = autoAccepted.add;
    Future<void> offer(String id, String attempt) async {
      await p.linkA.sendFileOffer(
        transferId: id,
        attemptId: attempt,
        mode: 'push',
        name: 'x.bin',
        size: 4,
        enc: true,
      );
      await pumpEventQueue(times: 60);
    }

    for (final (id, error) in [
      ('f-tamper', 'tampered'),
      ('f-net', 'network'),
    ]) {
      await offer(id, '$id-1');
      p.storeB.updateTransfer(
        id,
        (t) => t.copyWith(state: TransferState.failed, error: error),
      );
      await offer(id, '$id-2');
      expect(p.storeB.transfer(id)!.state, TransferState.offered);
    }
    expect(autoAccepted, ['f-net']);
  });
}
