import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';

Conversation _room({
  String? hostAlias,
  bool online = true,
  int memberCount = 3,
}) => Conversation(
  id: 'r',
  peerAlias: 'Room',
  peerPlatform: 'Room',
  transport: PeerTransport.app,
  startedAt: DateTime(2026),
  isRoom: true,
  hostAlias: hostAlias,
  online: online,
  memberCount: memberCount,
);

void main() {
  test('hostsGroupRoom is true only when this device hosts a live room', () {
    // 이 기기가 호스트, 게스트 둘 → room=1
    expect(hostsGroupRoom([_room()]), isTrue);
  });

  test('hostsGroupRoom is false when someone else hosts', () {
    expect(hostsGroupRoom([_room(hostAlias: 'blue-fox-12')]), isFalse);
  });

  test('hostsGroupRoom is false for an empty or solo room', () {
    expect(hostsGroupRoom([_room(memberCount: 1)]), isFalse);
    expect(hostsGroupRoom([_room(online: false)]), isFalse);
    expect(hostsGroupRoom(const []), isFalse);
  });

  test('hostsGroupRoom ignores 1:1 conversations', () {
    final direct = Conversation(
      id: 'c1',
      peerAlias: 'red-owl-9',
      peerPlatform: 'Linux',
      transport: PeerTransport.app,
      startedAt: DateTime(2026),
    );
    expect(hostsGroupRoom([direct]), isFalse);
  });

  test('PeerDevice carries the hostsRoom hint through copyWith', () {
    final peer = PeerDevice(
      peerId: 'p',
      alias: 'green-jay-4',
      platform: 'macOS',
      host: '192.168.1.4',
      port: 7890,
      seenAt: DateTime(2026),
    );
    expect(peer.hostsRoom, isFalse);
    expect(peer.copyWith(hostsRoom: true).hostsRoom, isTrue);
  });
}
