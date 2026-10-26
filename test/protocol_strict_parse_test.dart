import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/protocol.dart';

// 잘못된 숫자/필수 필드는 0/빈 문자열로 "정상 프레임"을 만들지 않고 MalformedInner로
// 명시적으로 거부됨. 파서는 어떤 입력에도 던지지 않음

Map<String, dynamic> _offer([Map<String, Object?> overrides = const {}]) {
  final base = <String, dynamic>{
    'k': 'file_offer',
    'id': 'f1',
    'at': 'a1',
    'md': 'push',
    'name': 'x.bin',
    'size': 4,
  };
  overrides.forEach((k, v) => v == null ? base.remove(k) : base[k] = v);
  return base;
}

InboundInner _parse(String json) =>
    InboundInner.fromJson(jsonDecode(json) as Map<String, dynamic>);

void main() {
  group('wireInt', () {
    test('accepts only JSON integers inside the range', () {
      expect(wireInt(5, min: 0, max: 10), 5);
      expect(wireInt(0, min: 0, max: 10), 0);
      expect(wireInt(10, min: 0, max: 10), 10);
    });

    test('rejects doubles, NaN, infinity, strings and out-of-range values', () {
      const bad = <Object?>[
        1.0,
        5.0,
        1.5,
        double.infinity,
        double.negativeInfinity,
        double.nan,
        '5',
        true,
        null,
        <int>[5],
        -1,
        11,
      ];
      for (final value in bad) {
        expect(
          wireInt(value, min: 0, max: 10),
          isNull,
          reason: 'wireInt must reject $value',
        );
      }
    });
  });

  group('file_offer required fields', () {
    test('a valid push offer still parses', () {
      final inner = InboundInner.fromJson(_offer());
      expect(inner, isA<FileOfferInner>());
      expect((inner as FileOfferInner).size, 4);
      expect(inner.mode, 'push');
    });

    test('1e999 / 1.0 / -1 / string / missing size are all malformed', () {
      for (final literal in <String>[
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x","size":1e999}',
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x","size":1.0}',
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x","size":-1}',
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x","size":"5"}',
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x","size":null}',
        '{"k":"file_offer","id":"f1","at":"a1","md":"push","name":"x"}',
      ]) {
        late InboundInner parsed;
        expect(
          () => parsed = _parse(literal),
          returnsNormally,
          reason: literal,
        );
        expect(parsed, isA<MalformedInner>(), reason: literal);
      }
    });

    test('empty, missing or non-token ids are malformed', () {
      for (final bad in <Map<String, Object?>>[
        {'id': ''},
        {'id': null},
        {'id': 'has space'},
        {'id': 'a/b'},
        {'id': 5},
        {'at': ''},
        {'at': null},
        {'at': 'x' * 129},
      ]) {
        expect(
          InboundInner.fromJson(_offer(bad)),
          isA<MalformedInner>(),
          reason: '$bad',
        );
      }
    });

    test('mode must be push or pull and never defaults', () {
      expect(
        InboundInner.fromJson(_offer({'md': null})),
        isA<MalformedInner>(),
      );
      expect(
        InboundInner.fromJson(_offer({'md': 'PUSH'})),
        isA<MalformedInner>(),
      );
      expect(InboundInner.fromJson(_offer({'md': 5})), isA<MalformedInner>());
    });

    test(
      'pull needs a token AND a private endpoint, push must have neither',
      () {
        final pull = _offer({
          'md': 'pull',
          'tok': 'tok-1',
          'sh': '192.168.1.9',
          'sp': 7890,
        });
        expect(InboundInner.fromJson(pull), isA<FileOfferInner>());

        for (final broken in <Map<String, Object?>>[
          {'tok': null},
          {'sh': null},
          {'sp': null},
          {'sh': '8.8.8.8'}, // WAN
          {'sh': '127.0.0.1'}, // loopback은 peer 주소가 아님
          {'sh': '010.0.0.1'}, // 비정규 표기
          {'sh': '10.1'},
          {'sp': 0},
          {'sp': 65536},
          {'sp': '7890'},
          {'tok': 'bad token'},
        ]) {
          final frame = Map<String, dynamic>.of(pull);
          broken.forEach((k, v) => v == null ? frame.remove(k) : frame[k] = v);
          expect(
            InboundInner.fromJson(frame),
            isA<MalformedInner>(),
            reason: '$broken',
          );
        }
        for (final extra in <Map<String, Object?>>[
          {'tok': 'tok-1'},
          {'sh': '192.168.1.9'},
          {'sp': 7890},
        ]) {
          expect(
            InboundInner.fromJson(_offer(extra)),
            isA<MalformedInner>(),
            reason: 'push offer must not carry $extra',
          );
        }
      },
    );

    test('optional fields that are present but malformed reject the frame', () {
      for (final bad in <Map<String, Object?>>[
        {'ttl': -1},
        {'ttl': 1.5},
        {'vc': 'yes'},
        {'ec': 1},
        {'bid': ''},
        {'mime': 5},
        {'name': ''},
        {'name': 5},
      ]) {
        expect(
          InboundInner.fromJson(_offer(bad)),
          isA<MalformedInner>(),
          reason: '$bad',
        );
      }
    });
  });
}
