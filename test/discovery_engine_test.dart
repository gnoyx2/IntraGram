import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/discovery_engine.dart';

BonsoirService _service({
  List<String> hostAddresses = const [],
  Map<String, String> attributes = const {},
  int port = 7890,
}) => BonsoirService.ignoreNorms(
  name: 'Intragram test',
  type: kServiceType,
  port: port,
  hostAddresses: hostAddresses,
  attributes: attributes,
);

void main() {
  group('BonsoirService.host', () {
    test('prefers an RFC1918 address over any other IPv4', () {
      final service = _service(hostAddresses: ['203.0.113.5', '192.168.1.42']);
      expect(service.host, '192.168.1.42');
    });

    test('falls back to a non-loopback IPv4 when no RFC1918 is present', () {
      final service = _service(hostAddresses: ['198.51.100.7']);
      expect(service.host, '198.51.100.7');
    });

    test('uses loopback only as a last resort', () {
      final service = _service(hostAddresses: ['127.0.0.1', '10.0.0.5']);
      expect(service.host, '10.0.0.5');
    });

    test('returns loopback when it is the only IPv4 address', () {
      final service = _service(hostAddresses: ['127.0.0.1']);
      expect(service.host, '127.0.0.1');
    });

    test('skips an IPv6 link-local address placed ahead of a valid IPv4 '
        '(Apple mDNS stack ordering)', () {
      final service = _service(hostAddresses: ['fe80::1', '192.168.1.9']);
      expect(service.host, '192.168.1.9');
    });

    test('returns null when unresolved (no addresses at all)', () {
      expect(_service().host, isNull);
    });
  });

  group('peerFromBonsoirService', () {
    test('maps attributes into a PeerDevice for a normal peer', () {
      final service = _service(
        hostAddresses: ['192.168.1.9'],
        attributes: const {
          'id': 'peer-1',
          'alias': 'blue-fox-12',
          'os': 'Linux',
          'room': '1',
          'inRoom': '1',
        },
      );
      final peer = peerFromBonsoirService(service, selfPeerId: 'me');
      expect(peer, isNotNull);
      expect(peer!.peerId, 'peer-1');
      expect(peer.alias, 'blue-fox-12');
      expect(peer.platform, 'Linux');
      expect(peer.host, '192.168.1.9');
      expect(peer.hostsRoom, isTrue);
      expect(peer.inRoom, isTrue);
    });

    test('an advertised os outside the app names reads as Unknown', () {
      final service = _service(
        hostAddresses: ['192.168.1.9'],
        attributes: const {'id': 'peer-1', 'os': 'Linux (totally real)'},
      );
      expect(
        peerFromBonsoirService(service, selfPeerId: 'me')!.platform,
        'Unknown',
      );
    });

    test('a room member (not host) advertises inRoom without room', () {
      final service = _service(
        hostAddresses: ['192.168.1.9'],
        attributes: const {'id': 'peer-1', 'inRoom': '1'},
      );
      final peer = peerFromBonsoirService(service, selfPeerId: 'me');
      expect(peer!.hostsRoom, isFalse);
      expect(peer.inRoom, isTrue);
    });

    test('filters out the device itself', () {
      final service = _service(
        hostAddresses: ['192.168.1.9'],
        attributes: const {'id': 'me'},
      );
      expect(peerFromBonsoirService(service, selfPeerId: 'me'), isNull);
    });

    test('filters out a service whose host is not link-local/private', () {
      final service = _service(
        hostAddresses: ['203.0.113.5'],
        attributes: const {'id': 'peer-1'},
      );
      expect(peerFromBonsoirService(service, selfPeerId: 'me'), isNull);
    });

    test('filters out an unresolved service (no host yet)', () {
      final service = _service(attributes: const {'id': 'peer-1'});
      expect(peerFromBonsoirService(service, selfPeerId: 'me'), isNull);
    });
  });

  group('isDiscoveryPeerStale', () {
    final now = DateTime(2026, 1, 1, 12);

    test('is not stale just under the cutoff', () {
      final seenAt = now.subtract(
        kDiscoveryRefresh * 3 - const Duration(seconds: 1),
      );
      expect(isDiscoveryPeerStale(seenAt, now), isFalse);
    });

    test('is stale just past the cutoff', () {
      final seenAt = now.subtract(
        kDiscoveryRefresh * 3 + const Duration(seconds: 1),
      );
      expect(isDiscoveryPeerStale(seenAt, now), isTrue);
    });
  });

  group('DiscoveryController broadcast serialization', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'back-to-back room hint updates stop prior broadcast first and coalesce',
      () {
        fakeAsync((async) {
          var active = 0;
          var maxActive = 0;
          final started = <BonsoirService>[];
          final original = DiscoveryController.createBroadcast;
          DiscoveryController.createBroadcast = (service) => _DelayedBroadcast(
            service,
            onStart: () {
              active++;
              if (active > maxActive) maxActive = active;
              started.add(service);
            },
            onStop: () => active--,
          );
          addTearDown(() => DiscoveryController.createBroadcast = original);

          final container = ProviderContainer();
          addTearDown(container.dispose);
          final identity = AppIdentity(
            peerId: 'me',
            alias: 'swift-heron-3',
            platform: 'iOS',
          );
          final notifier = container.read(discoveryControllerProvider.notifier);

          unawaited(notifier.start(identity: identity, port: 7890));
          async.elapse(const Duration(seconds: 2));
          expect(started, hasLength(1));
          expect(active, 1);

          // 이전 버그 재현: setHostsRoom(true)와 setInRoom(true)를 동시에 발사해도 중복 등록 없이 1회만 재시작
          unawaited(notifier.setHostsRoom(true));
          unawaited(notifier.setInRoom(true));
          async.elapse(const Duration(milliseconds: 200));

          expect(maxActive, 1);
          expect(active, 1);
          expect(started, hasLength(2));
          expect(started.last.attributes['room'], '1');
          expect(started.last.attributes['inRoom'], '1');

          // 이름 변경이 없으면 restartBroadcast는 불필요한 재등록을 건너뛰고, 바뀌면 안전하게 교체
          unawaited(notifier.restartBroadcast());
          async.elapse(const Duration(milliseconds: 200));
          expect(started, hasLength(2));

          identity.rename('bright-lynx-8');
          unawaited(notifier.restartBroadcast());
          async.elapse(const Duration(milliseconds: 200));
          expect(maxActive, 1);
          expect(started, hasLength(3));
          expect(started.last.name, 'Intragram bright-lynx-8');

          unawaited(notifier.stop());
          async.elapse(const Duration(milliseconds: 200));
          expect(active, 0);
        });
      },
    );
  });
}

class _DelayedBroadcast implements BroadcastSession {
  _DelayedBroadcast(
    this.service, {
    required this.onStart,
    required this.onStop,
  });

  final BonsoirService service;
  final void Function() onStart;
  final void Function() onStop;
  bool _running = false;

  @override
  Future<void> initialize() =>
      Future<void>.delayed(const Duration(milliseconds: 10));

  @override
  Future<void> start() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _running = true;
    onStart();
  }

  @override
  Future<void> stop() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (_running) {
      _running = false;
      onStop();
    }
  }
}
