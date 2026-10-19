import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'handshake_pair.dart';
import 'test_identities.dart';

// 인가 테스트 공용 rig: A가 보내는 쪽(다이얼러), B가 받는 쪽(호스트 허브 역할이라 relay 콜백이 걸려 있음)
class AuthRig {
  AuthRig._(this.linkA, this.linkB, this.storeA, this.storeB);

  final PeerLink linkA;
  final PeerLink linkB;
  final InMemoryStore storeA;
  final InMemoryStore storeB;

  // B의 onRoomFrame(= 방 멤버에게 relay하는 콜백)이 받은 프레임
  final List<Map<String, dynamic>> relayed = <Map<String, dynamic>>[];

  static Future<AuthRig> create() async {
    final p = await connectedPair();
    final rig = AuthRig._(p.linkA, p.linkB, p.storeA, p.storeB);
    p.linkB.onRoomFrame = rig.relayed.add;
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });
    return rig;
  }

  Future<void> sendFromA(Map<String, dynamic> frame) async {
    await linkA.sendRawInner(frame);
    await pumpEventQueue(times: 60);
  }
}

// 1:1 대화의 정상 offer wire(암호화 표시 포함): extra로 필드를 바꾸거나 null로 지움
Map<String, dynamic> authOffer(
  String id, {
  Map<String, Object?> extra = const {},
}) {
  final frame = <String, dynamic>{
    'k': 'file_offer',
    'id': id,
    'at': 'a1',
    'md': 'push',
    'name': 'x.bin',
    'size': 4,
    'ec': true,
  };
  extra.forEach((k, v) => v == null ? frame.remove(k) : frame[k] = v);
  return frame;
}

FileTransfer authTransfer(
  String id,
  String conversationId,
  TransferDirection direction, {
  TransferState state = TransferState.offered,
}) => FileTransfer(
  id: id,
  conversationId: conversationId,
  direction: direction,
  fileName: 'x.bin',
  totalBytes: 4,
  state: state,
  attemptId: 'a1',
  encrypted: true,
  mode: FileTransferMode.push,
  senderPeerId: direction == TransferDirection.incoming
      ? testPeerId('a')
      : null,
);
