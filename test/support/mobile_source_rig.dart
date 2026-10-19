import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'fake_file_source_channel.dart';
import 'transfer_rig.dart';

// mobile_source_*_test.dart가 공유하는 리그: 그룹 방(pull) 멤버
// 둘을 실제 서버/링크로 이어 놓고 가짜 intragram/file_source 채널로
// 방에 네이티브 소스를 제안/수신/취소해 봄
class MobileSourceRig {
  MobileSourceRig._(this.fake, this.rig, this.roomId);

  final FakeFileSourceChannel fake;
  final TransferRig rig;
  final String roomId;

  static Future<MobileSourceRig> create() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final fake = FakeFileSourceChannel()..install();
    final rig = await TransferRig.create(
      ackTimeout: const Duration(milliseconds: 250),
      members: 2,
    );
    return MobileSourceRig._(fake, rig, await rig.formRoom());
  }

  OutgoingTransfers get out => rig.registry.debugOutgoing;
  TransferState state(String id) => rig.store.transfer(id)!.state;

  Future<String> offer({int count = 1}) async {
    fake.pickCount = count;
    await rig.registry.offerStreamSources(
      roomId,
      await MobileFileSource.pick(),
    );
    return rig.store.transfers.first.id;
  }

  ({String key, String attemptId, String? pullToken, String phase}) rec(
    String id,
    int i,
  ) => out.debugRecipients(id).firstWhere((r) => r.key == TransferRig.keyOf(i));

  // i번째 멤버가 자기 토큰/attempt로 GET을 시작함 (body는 아직 안 읽음)
  Future<OutgoingDownload?> openGet(String id, int i) => out.openDownload(
    transferId: id,
    attemptId: rec(id, i).attemptId,
    token: rec(id, i).pullToken!,
    declaredSize: rig.store.transfer(id)!.totalBytes,
  );

  Future<void> pullAll(String id, int i) async =>
      (await openGet(id, i))!.body.drain<void>();

  void ack(String id, int i) => out.handleFileReceived(
    id,
    attemptId: rec(id, i).attemptId,
    actorKey: TransferRig.keyOf(i),
  );

  // 마지막 reader close가 첫 release보다 앞서는가
  bool closedBeforeRelease() =>
      fake.log.lastIndexWhere((e) => e.startsWith('close:')) <
      fake.indexOf('release:s1');
}

// 비동기 착수(open/read/close/release)가 끝나게 이벤트 큐를 충분히 돌림
Future<void> settle() => pumpEventQueue(times: 60);
