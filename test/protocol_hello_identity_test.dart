import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/protocol.dart';

// hello가 밝힌 신원(peerId·alias)은 방 프레임에 그대로 실림: 형식이 틀리거나 너무 길면
// 다른 멤버의 엄격 파서가 방 명단/입장 프레임 전체를 거부하게 되므로 hello 단계에서 거름
void main() {
  String hello({
    Object? peerId = 'ab12',
    Object? alias = 'fox',
    String? type,
  }) => jsonEncode(<String, Object?>{
    't': type ?? 'hello',
    'v': kProtocolVersion,
    'peerId': peerId,
    'alias': alias,
    'platform': 'test',
    'cmt': base64.encode(List<int>.filled(32, 2)),
    'idk': base64.encode(List<int>.filled(32, 1)), // 형식만 맞으면 됨(신원 검증은 링크가 함)
  });

  group('a hello with a malformed peerId is dropped', () {
    for (final bad in <Object?>[
      '',
      'x y',
      'a/b',
      'é',
      'a' * 129,
      42,
      null,
      <String>['a'],
    ]) {
      test('peerId=$bad', () {
        expect(InboundOuter.parse(hello(peerId: bad)), isA<MalformedOuter>());
      });
    }

    for (final good in <String>['ab12', 'a' * 32, 'A_b-c=', 'z' * 128]) {
      test('peerId=$good passes', () {
        final parsed = InboundOuter.parse(hello(peerId: good));
        expect(parsed, isA<HelloOuter>());
        expect((parsed as HelloOuter).peerId, good);
      });
    }
  });

  group('an over-long alias is cut at a character boundary', () {
    String aliasOf(String raw, {String type = 'hello'}) {
      final parsed = InboundOuter.parse(hello(alias: raw, type: type));
      return switch (parsed) {
        HelloOuter(:final alias) => alias,
        WebHelloOuter(:final alias) => alias,
        _ => fail('unexpected $parsed'),
      };
    }

    test('ascii', () => expect(aliasOf('a' * 1000), 'a' * 256));

    test('multi-byte characters are never split', () {
      final cut = aliasOf('가' * 200);
      expect(cut, '가' * 85, reason: '85 x 3 bytes = 255 <= 256');
      expect(utf8.encode(cut).length, lessThanOrEqualTo(256));
    });

    test('an alias within the limit is unchanged', () {
      expect(aliasOf('blue-fox-42'), 'blue-fox-42');
      expect(aliasOf('가' * 85), '가' * 85);
    });

    test('a browser guest alias is bounded too', () {
      expect(aliasOf('b' * 500, type: 'web_hello'), 'b' * 256);
    });

    test('the bounded alias still fits a room frame', () {
      final alias = boundedAlias('😀' * 300);
      final parsed = InboundInner.fromJson(<String, dynamic>{
        'k': 'room_state',
        'count': 2,
        'joined': alias,
      });
      expect(parsed, isA<RoomStateInner>());
    });
  });
}
