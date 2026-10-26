import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';

Conversation _room({
  String? hostAlias,
  bool online = true,
  int memberCount = 3,
  PeerTransport transport = PeerTransport.app,
}) => Conversation(
  id: 'r',
  peerAlias: 'Room',
  peerPlatform: 'Room',
  transport: transport,
  startedAt: DateTime(2026),
  isRoom: true,
  hostAlias: hostAlias,
  online: online,
  memberCount: memberCount,
);

class _FakeBroadcast implements BroadcastSession {
  _FakeBroadcast(this.service, this.tracker);
  final BonsoirService service;
  final _BroadcastTracker tracker;
  bool active = false;

  @override
  Future<void> initialize() async => Future<void>.delayed(Duration.zero);

  @override
  Future<void> start() async {
    active = true;
    tracker.activeCount++;
    if (tracker.activeCount > tracker.maxConcurrentActive) {
      tracker.maxConcurrentActive = tracker.activeCount;
    }
    tracker.started.add(service);
  }

  @override
  Future<void> stop() async {
    if (active) {
      active = false;
      tracker.activeCount--;
    }
  }
}

class _BroadcastTracker {
  final List<BonsoirService> started = <BonsoirService>[];
  int activeCount = 0;
  int maxConcurrentActive = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test(
    'web guest portal rooms do not advertise app-peer room hints on mDNS',
    () {
      final portalRoom = _room(transport: PeerTransport.web, memberCount: 2);
      expect(hostsGroupRoom([portalRoom]), isFalse);
      expect(inAnyGroupRoom([portalRoom]), isFalse);
      expect(inAnyGroupRoom([_room(hostAlias: 'blue-fox-12')]), isTrue);
    },
  );

  test(
    'roomHintBridge ignores web portal guests and serializes app room hints',
    () {
      fakeAsync((async) {
        final tracker = _BroadcastTracker();
        final originalFactory = DiscoveryController.createBroadcast;
        DiscoveryController.createBroadcast = (service) =>
            _FakeBroadcast(service, tracker);
        addTearDown(
          () => DiscoveryController.createBroadcast = originalFactory,
        );

        final identity = AppIdentity(
          peerId: 'host-peer',
          alias: 'calm-otter-7',
          platform: 'iOS',
        );
        final container = ProviderContainer(
          overrides: [appIdentityProvider.overrideWithValue(identity)],
        );
        addTearDown(container.dispose);

        final sub = container.listen(roomHintBridgeProvider, (_, _) {});
        addTearDown(sub.close);
        unawaited(
          container
              .read(discoveryControllerProvider.notifier)
              .start(identity: identity, port: 7890),
        );
        async.elapse(const Duration(seconds: 2));
        expect(tracker.started, hasLength(1));

        final store = container.read(inMemoryStoreProvider);
        // 브라우저 게스트 포털 입장 시나리오: 임시 대화 → 웹 방 생성 → 인원 갱신
        store.upsertConversation(
          _room(transport: PeerTransport.web, memberCount: 1),
        );
        store.updateConversation('r', (c) => c.copyWith(memberCount: 2));
        async.elapse(const Duration(milliseconds: 100));
        expect(tracker.started, hasLength(1));
        expect(tracker.maxConcurrentActive, 1);

        // 앱 그룹 방 생성·인원 갱신 시에도 기존 광고 정지 후 다음 광고가 시작돼 동시 활성 수는 1을 넘지 않음
        store.upsertConversation(
          Conversation(
            id: 'app-room',
            peerAlias: 'Room',
            peerPlatform: 'Room',
            transport: PeerTransport.app,
            startedAt: DateTime(2026),
            isRoom: true,
            online: true,
            memberCount: 1,
          ),
        );
        store.updateConversation('app-room', (c) => c.copyWith(memberCount: 2));
        async.elapse(const Duration(milliseconds: 100));

        expect(tracker.maxConcurrentActive, 1);
        expect(tracker.activeCount, 1);
        expect(tracker.started.last.attributes['room'], '1');
        expect(tracker.started.last.attributes['inRoom'], '1');
      });
    },
  );

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
