import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/discovery_engine.dart';

BonsoirService _service({
  List<String> hostAddresses = const [],
  Map<String, String> attributes = const {},
  int port = 7890,
}) => BonsoirService.ignoreNorms(
  name: 'IntraGram test',
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
}
