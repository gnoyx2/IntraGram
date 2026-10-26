import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/protocol.dart';

// 잘못된 숫자/필수 필드는 0/빈 문자열로 "정상 프레임"을 만들지 않고 MalformedInner로
// 명시적으로 거부됨. 파서는 어떤 입력에도 던지지 않음

void main() {
  group('other kinds', () {
    test('required ids, counts and booleans are enforced', () {
      const bad = <Map<String, Object?>>[
        {'k': 'msg', 'text': 'hi'}, // id 없음
        {'k': 'msg', 'id': 'm1'}, // text 없음
        {'k': 'msg', 'id': 'm1', 'text': 'hi', 'ttl': '30'},
        {'k': 'msg', 'id': 'm1', 'text': 'hi', 'ts': 1.5},
        {'k': 'read'},
        {'k': 'burn', 'id': ''},
        {'k': 'rename', 'alias': 'x'}, // pid 없음
        {'k': 'rename', 'alias': '', 'pid': 'p1'},
        {'k': 'typing'},
        {'k': 'typing', 'on': 'true'},
        {'k': 'react', 'id': 'm1', 'emoji': '👍'}, // on 없음
        {'k': 'react', 'id': 'm1', 'emoji': '', 'on': true},
        {'k': 'room_join'},
        {'k': 'room_join', 'count': '2'},
        {'k': 'room_join', 'count': 2.0},
        {'k': 'room_state', 'count': -1},
        {'k': 'file_accept', 'id': 'f1', 'at': 'a1'}, // tok 없음
        {'k': 'file_accept', 'id': 'f1', 'tok': 't'}, // at 없음
        {'k': 'file_reject', 'id': 'f1'},
        {'k': 'file_cancel', 'id': 'f1'},
        {'k': 'file_received', 'id': 'f1'},
        {'k': 'file_retry', 'id': 'f1'},
      ];
      for (final frame in bad) {
        final parsed = InboundInner.fromJson(Map<String, dynamic>.of(frame));
        expect(parsed, isA<MalformedInner>(), reason: '$frame');
      }
    });

    test('valid frames from the app and the browser keep parsing', () {
      const good = <Map<String, Object?>>[
        {'k': 'msg', 'id': 'm1', 'text': 'hi', 'ttl': 0, 'ts': 1700000000000},
        {'k': 'msg', 'id': 'm1', 'text': ''}, // 브라우저는 ttl/ts를 생략할 수 있음
        {'k': 'read', 'id': 'm1'},
        {'k': 'verify'},
        {'k': 'rename', 'alias': 'blue-fox-12', 'pid': 'peer-1'},
        {'k': 'burn', 'id': 'm1'},
        {'k': 'screenshot'},
        {'k': 'typing', 'on': true},
        {'k': 'react', 'id': 'm1', 'emoji': '👍', 'on': false},
        {'k': 'room_join', 'count': 3},
        {'k': 'room_state', 'count': 3, 'joined': 'a', 'left': 'b'},
        {'k': 'file_accept', 'id': 'f1', 'at': 'a1', 'tok': 'tok-1'},
        {'k': 'file_reject', 'id': 'f1', 'at': 'a1'},
        {'k': 'file_cancel', 'id': 'f1', 'at': 'a1'},
        {'k': 'file_received', 'id': 'f1', 'at': 'a1'},
        {'k': 'file_retry', 'id': 'f1', 'at': 'a1'},
      ];
      for (final frame in good) {
        final parsed = InboundInner.fromJson(Map<String, dynamic>.of(frame));
        expect(parsed, isNot(isA<MalformedInner>()), reason: '$frame');
        expect(parsed, isNot(isA<UnknownInner>()), reason: '$frame');
      }
    });

    test('an unknown kind is an UnknownInner, never a typed frame', () {
      expect(
        InboundInner.fromJson(<String, dynamic>{'k': 'file_wipe', 'id': 'f1'}),
        isA<UnknownInner>(),
      );
      expect(InboundInner.fromJson(<String, dynamic>{}), isA<UnknownInner>());
    });
  });
}
