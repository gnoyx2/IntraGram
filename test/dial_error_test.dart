import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/link_registry.dart';

// IP 직결이 왜 실패했는지 가려서 안내함: 응답 없음, 거부, 경로 없음, Intragram 아님
void main() {
  SocketException os(int code) =>
      SocketException('connect', osError: OSError('x', code));

  test('a timeout means nothing answered', () {
    expect(
      classifyDialError(TimeoutException('t')),
      PeerUnreachableReason.noAnswer,
    );
    for (final code in [60, 110, 10060]) {
      expect(classifyDialError(os(code)), PeerUnreachableReason.noAnswer);
    }
  });

  test('a refused connection means the device is there', () {
    for (final code in [61, 111, 10061]) {
      expect(classifyDialError(os(code)), PeerUnreachableReason.refused);
    }
  });

  test('no route covers other networks and a blocked local network', () {
    for (final code in [51, 65, 101, 113, 10051, 10065, 64, 112, 10064]) {
      expect(classifyDialError(os(code)), PeerUnreachableReason.noRoute);
    }
  });

  test('an answer that is not a WebSocket upgrade is not Intragram', () {
    expect(
      classifyDialError(const WebSocketException('not upgraded')),
      PeerUnreachableReason.notIntragram,
    );
    expect(
      classifyDialError(const HttpException('bad response')),
      PeerUnreachableReason.notIntragram,
    );
  });

  test('anything else falls back to no answer', () {
    expect(
      classifyDialError(const SocketException('no os error')),
      PeerUnreachableReason.noAnswer,
    );
  });
}
