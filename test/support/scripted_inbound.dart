import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/link_registry.dart';

import 'scripted_peer.dart';

// [registry]에 [host]에서 온 인바운드 소켓 하나를 열고, [identity]를 가진 스크립트 다이얼러가
// 정직하게 신원을 증명해 링크가 secure가 되게 함(증명 전 상태를 보려면 [proveIdentity]를 끔)
Future<ScriptedPeer> connectScriptedInbound(
  LinkRegistry registry, {
  required String host,
  required AppIdentity identity,
  int port = 7890,
  bool proveIdentity = true,
}) async {
  final wire = StreamChannelController<dynamic>();
  final peer = await ScriptedPeer.create(identity, wire.local);
  await registry.acceptInbound(
    wire.foreign,
    remoteHost: host,
    remotePort: port,
  );
  peer.sendDialerHello();
  await pumpEventQueue(times: 60);
  await peer.completeHandshake();
  if (proveIdentity) {
    peer.sendAuth(await peer.proof(asDialer: true));
    await pumpEventQueue(times: 60);
  }
  return peer;
}
