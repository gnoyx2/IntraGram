import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart';

void main() {
  group('isRfc1918', () {
    test('accepts every RFC 1918 range', () {
      expect(NetworkGuard.isRfc1918('10.0.0.1'), isTrue);
      expect(NetworkGuard.isRfc1918('10.255.255.255'), isTrue);
      expect(NetworkGuard.isRfc1918('172.16.0.1'), isTrue);
      expect(NetworkGuard.isRfc1918('172.31.255.255'), isTrue);
      expect(NetworkGuard.isRfc1918('192.168.1.15'), isTrue);
    });

    test('rejects public addresses and near-misses', () {
      expect(NetworkGuard.isRfc1918('8.8.8.8'), isFalse);
      expect(NetworkGuard.isRfc1918('172.15.0.1'), isFalse);
      expect(NetworkGuard.isRfc1918('172.32.0.1'), isFalse);
      expect(NetworkGuard.isRfc1918('192.169.0.1'), isFalse);
      expect(NetworkGuard.isRfc1918('127.0.0.1'), isFalse);
      expect(NetworkGuard.isRfc1918('garbage'), isFalse);
      expect(NetworkGuard.isRfc1918('192.168.1'), isFalse);
      expect(NetworkGuard.isRfc1918('300.1.1.1'), isFalse);
    });
  });

  group('isLinkLocalOrPrivate', () {
    test('also accepts loopback and APIPA', () {
      expect(NetworkGuard.isLinkLocalOrPrivate('127.0.0.1'), isTrue);
      expect(NetworkGuard.isLinkLocalOrPrivate('169.254.10.20'), isTrue);
      expect(NetworkGuard.isLinkLocalOrPrivate('192.168.0.5'), isTrue);
    });

    test('still rejects the public internet', () {
      expect(NetworkGuard.isLinkLocalOrPrivate('1.1.1.1'), isFalse);
      expect(NetworkGuard.isLinkLocalOrPrivate('93.184.216.34'), isFalse);
    });
  });

  group('parsePeerQr', () {
    test('accepts an http(s) URL with a private IPv4 and port', () {
      expect(NetworkGuard.parsePeerQr('http://192.168.1.9:7890'), (
        host: '192.168.1.9',
        port: 7890,
      ));
      expect(NetworkGuard.parsePeerQr('  https://10.0.0.4:8443/  '), (
        host: '10.0.0.4',
        port: 8443,
      ));
    });

    test('rejects a WAN address, a hostname, and a bare IP', () {
      expect(NetworkGuard.parsePeerQr('http://8.8.8.8:7890'), isNull);
      expect(NetworkGuard.parsePeerQr('http://example.com:7890'), isNull);
      expect(NetworkGuard.parsePeerQr('192.168.1.9:7890'), isNull);
    });

    test('rejects a non-http scheme and a missing port', () {
      expect(NetworkGuard.parsePeerQr('ftp://192.168.1.9:21'), isNull);
      expect(NetworkGuard.parsePeerQr('http://192.168.1.9'), isNull);
      expect(NetworkGuard.parsePeerQr('not a url at all'), isNull);
    });

    test('rejects noncanonical and internal-only peer addresses', () {
      for (final host in [
        '010.0.0.1',
        '0x0a.0.0.1',
        '10.1',
        '127.0.0.1',
        '169.254.1.1',
        '[fd12:3456::1]',
      ]) {
        expect(NetworkGuard.parsePeerQr('http://$host:7890'), isNull);
      }
      expect(NetworkGuard.parsePeerQr('http://u@10.0.0.1:7890'), isNull);
    });
  });

  group('assertReachable', () {
    test('passes for a link-local IPv4 target', () {
      expect(
        () => NetworkGuard.assertReachable(InternetAddress('192.168.1.20')),
        returnsNormally,
      );
    });

    test('throws SecurityException for a WAN target', () {
      expect(
        () => NetworkGuard.assertReachable(InternetAddress('1.1.1.1')),
        throwsA(isA<SecurityException>()),
      );
    });

    test('passes for an IPv6 ULA target', () {
      expect(
        () => NetworkGuard.assertReachable(
          InternetAddress('fd00::1', type: InternetAddressType.IPv6),
        ),
        returnsNormally,
      );
    });

    test('throws SecurityException for an IPv6 GUA (global) target', () {
      expect(
        () => NetworkGuard.assertReachable(
          InternetAddress('2001:db8::1', type: InternetAddressType.IPv6),
        ),
        throwsA(isA<SecurityException>()),
      );
    });
  });

  group('createPeerHttpClient', () {
    test('exists and can be closed', () {
      final client = NetworkGuard.createPeerHttpClient();
      client.close(force: true);
    });
  });

  group('peerConnectionFactory (the connectionFactory createPeerHttpClient '
      'installs — the choke point every socket this client opens must pass, '
      'first hop or redirect target alike)', () {
    test('refuses to resolve a hostname (no DNS lookup)', () async {
      await expectLater(
        peerConnectionFactory(Uri.parse('http://example.com:80/'), null, null),
        throwsA(isA<SecurityException>()),
      );
    });

    test('refuses a WAN IPv4 target', () async {
      await expectLater(
        peerConnectionFactory(Uri.parse('http://8.8.8.8:80/'), null, null),
        throwsA(isA<SecurityException>()),
      );
    });

    test('opens a real socket for an allowed loopback target', () async {
      final serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => serverSocket.close());

      final task = await peerConnectionFactory(
        Uri(scheme: 'http', host: '127.0.0.1', port: serverSocket.port),
        null,
        null,
      );
      final socket = await task.socket;
      socket.destroy();
    });
  });

  group('IPv6 support', () {
    test('isLinkLocalOrPrivate accepts loopback and ULA, rejects GUA', () {
      expect(NetworkGuard.isLinkLocalOrPrivate('::1'), isTrue);
      expect(NetworkGuard.isLinkLocalOrPrivate('fd12:3456::1'), isTrue);
      expect(NetworkGuard.isLinkLocalOrPrivate('fc00::1'), isTrue);
      expect(NetworkGuard.isLinkLocalOrPrivate('2001:db8::1'), isFalse);
      expect(
        NetworkGuard.isLinkLocalOrPrivate('2001:4860:4860::8888'),
        isFalse,
      );
    });

    test(
      'isLinkLocalOrPrivate rejects IPv6 link-local (no scope id support)',
      () {
        // 알려진 한계: fe80::/10은 실제로 다이얼하려면 zone
        // id(%en0)가 필요한데 discovery/QR이 아직
        // 안 실음
        expect(NetworkGuard.isLinkLocalOrPrivate('fe80::1'), isFalse);
      },
    );

    test('parsePeerQr rejects a bracketed IPv6 GUA URL', () {
      expect(NetworkGuard.parsePeerQr('http://[2001:db8::1]:7890'), isNull);
    });

    test('hostForUri brackets IPv6 but leaves IPv4 alone', () {
      expect(NetworkGuard.hostForUri('192.168.1.9'), '192.168.1.9');
      expect(NetworkGuard.hostForUri('fd12:3456::1'), '[fd12:3456::1]');
    });
  });

  // 대역 순위만으로 고르면 VM·테더링 브리지, VPN, 셀룰러가 받은 사설 주소에 바인드해서 LAN 상대가 못 닿음
  group('pickBindAddress', () {
    String? pick(List<(String, String)> ifaces) => NetworkGuard.pickBindAddress(
      [for (final (name, ip) in ifaces) (name, InternetAddress(ip))],
    )?.address;

    test('real Wi-Fi beats a VM bridge, VPN or cellular address', () {
      expect(
        pick([('bridge100', '192.168.64.1'), ('en0', '172.30.1.94')]),
        '172.30.1.94',
      );
      expect(
        pick([('pdp_ip0', '10.20.30.40'), ('en0', '10.0.0.5')]),
        '10.0.0.5',
      );
      expect(
        pick([('vEthernet (WSL)', '172.25.0.1'), ('Wi-Fi', '172.30.1.10')]),
        '172.30.1.10',
      );
      expect(
        pick([('rmnet_data0', '10.1.2.3'), ('wlan0', '172.16.4.2')]),
        '172.16.4.2',
      );
    });

    test('a lone hotspot bridge is used, link-local comes last', () {
      expect(pick([('bridge100', '172.20.10.1')]), '172.20.10.1');
      expect(
        pick([('en0', '169.254.7.7'), ('vmnet8', '192.168.100.1')]),
        '192.168.100.1',
      );
      expect(pick([('en0', '8.8.8.8')]), isNull);
    });

    test('between physical interfaces the address range still decides', () {
      expect(
        pick([('en0', '10.0.0.2'), ('en1', '192.168.1.2')]),
        '192.168.1.2',
      );
    });
  });
}
