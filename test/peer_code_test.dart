import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/peer_code.dart';

// 앱끼리 잇는 QR: 기기 코드와 포털 주소 둘 다 읽고, 실린 peerId로 연결 상대를 고정함
void main() {
  const peerId = '0123456789abcdef0123456789abcdef';

  test('a device code round-trips with its identity', () {
    final code = deviceCode(host: '192.168.0.7', port: 7890, peerId: peerId);
    expect(code, 'intragram://192.168.0.7:7890/$peerId');
    expect(parsePeerCode(code), (
      host: '192.168.0.7',
      port: 7890,
      peerId: peerId,
    ));
  });

  test('a portal QR from an app pins the host identity', () {
    final code = portalCodeWithPeer('http://10.0.0.4:7890#t=abc', peerId);
    expect(parsePeerCode(code), (host: '10.0.0.4', port: 7890, peerId: peerId));
  });

  test('a plain portal address still connects without a pinned identity', () {
    expect(parsePeerCode('http://10.0.0.4:7890#t=abc'), (
      host: '10.0.0.4',
      port: 7890,
      peerId: null,
    ));
  });

  group('codes that are refused', () {
    for (final bad in <String>[
      'intragram://192.168.0.7:7890/NOT-HEX',
      'intragram://192.168.0.7:7890/${peerId}00',
      'intragram://192.168.0.7:7890/$peerId/extra',
      'intragram://192.168.0.7/$peerId',
      'intragram://8.8.8.8:7890/$peerId',
      'intragram://router.local:7890/$peerId',
      'intragram://user@192.168.0.7:7890/$peerId',
      'intragram://192.168.0.7:7890/$peerId?x=1',
      'http://10.0.0.4:7890#t=abc&p=short',
      'http://8.8.8.8:7890#t=abc&p=$peerId',
      'ftp://10.0.0.4:7890/$peerId',
    ]) {
      test(bad, () => expect(parsePeerCode(bad), isNull));
    }
  });
}
