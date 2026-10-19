import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/protocol.dart';

void main() {
  test('inner message frame round-trips', () {
    final inner = InboundInner.fromJson(
      InnerFrame.message(id: 'm1', text: 'hi', ttlSeconds: 30, timestampMs: 9),
    );
    expect(inner, isA<MessageInner>());
    inner as MessageInner;
    expect(inner.text, 'hi');
    expect(inner.ttlSeconds, 30);
    expect(inner.replyToId, isNull);
  });

  test('a reply message carries the parent id and a relayed sender', () {
    final frame = InnerFrame.message(
      id: 'm2',
      text: 'agreed',
      ttlSeconds: 0,
      timestampMs: 1,
      replyToId: 'm1',
    );
    expect(frame['re'], 'm1');

    final inner =
        InboundInner.fromJson(<String, dynamic>{
              ...frame,
              'from': 'blue-fox-12',
            })
            as MessageInner;
    expect(inner.replyToId, 'm1');
    expect(inner.from, 'blue-fox-12');
  });

  test('ack frame round-trips and needs an id', () {
    final inner = InboundInner.fromJson(InnerFrame.ack('m1'));
    expect(inner, isA<AckInner>());
    expect((inner as AckInner).id, 'm1');
    expect(
      InboundInner.fromJson(<String, dynamic>{'k': 'ack'}),
      isA<MalformedInner>(),
    );
  });

  test('react frame round-trips', () {
    final frame = InnerFrame.react(id: 'm1', emoji: '👍', on: true);
    expect(frame['k'], 'react');
    final inner =
        InboundInner.fromJson(<String, dynamic>{...frame, 'from': 'a'})
            as ReactInner;
    expect(inner.id, 'm1');
    expect(inner.emoji, '👍');
    expect(inner.on, isTrue);
    expect(inner.from, 'a');
  });

  test('room_state frame round-trips with an optional joined/left alias', () {
    final counted = InboundInner.fromJson(InnerFrame.roomState(count: 3));
    expect(counted, isA<RoomStateInner>());
    expect((counted as RoomStateInner).count, 3);
    expect(counted.joined, isNull);
    expect(counted.left, isNull);

    final joined =
        InboundInner.fromJson(
              InnerFrame.roomState(count: 4, joined: 'blue-fox-12'),
            )
            as RoomStateInner;
    expect(joined.joined, 'blue-fox-12');

    final left =
        InboundInner.fromJson(InnerFrame.roomState(count: 2, left: 'red-owl-9'))
            as RoomStateInner;
    expect(left.left, 'red-owl-9');
  });

  test('file_cancel round-trips', () {
    final frame = InnerFrame.fileCancel('f9', attempt: 'a9');
    expect(frame, <String, dynamic>{
      'k': 'file_cancel',
      'id': 'f9',
      'at': 'a9',
    });
    final inner = InboundInner.fromJson(frame);
    expect(inner, isA<FileCancelInner>());
    expect((inner as FileCancelInner).id, 'f9');
    expect(inner.attempt, 'a9');
  });

  test('screenshot inner round-trips, carrying an optional relay tag', () {
    final frame = InnerFrame.screenshot();
    expect(frame, <String, dynamic>{'k': 'screenshot'});

    final direct = InboundInner.fromJson(frame);
    expect(direct, isA<ScreenshotInner>());
    expect((direct as ScreenshotInner).from, isNull);

    final relayed = InboundInner.fromJson(<String, dynamic>{
      ...frame,
      'from': 'blue-otter-9',
    });
    expect((relayed as ScreenshotInner).from, 'blue-otter-9');
  });

  test('file_unavailable round-trips without any sender field', () {
    final frame = InnerFrame.fileUnavailable(
      'f1',
      attempt: 'a1',
      target: 'peer9',
    );
    expect(frame, <String, dynamic>{
      'k': 'file_unavailable',
      'id': 'f1',
      'at': 'a1',
      'to': 'peer9',
    });

    final inner = InboundInner.fromJson(frame);
    expect(inner, isA<FileUnavailableInner>());
    inner as FileUnavailableInner;
    expect((inner.id, inner.attempt, inner.target), ('f1', 'a1', 'peer9'));
  });

  test('a file_unavailable missing a field or with a bad one is malformed', () {
    for (final bad in <Map<String, dynamic>>[
      {'k': 'file_unavailable', 'at': 'a1', 'to': 'p'},
      {'k': 'file_unavailable', 'id': 'f1', 'to': 'p'},
      {'k': 'file_unavailable', 'id': 'f1', 'at': 'a1'},
      {'k': 'file_unavailable', 'id': 'f1', 'at': 'a1', 'to': 'has space'},
      {'k': 'file_unavailable', 'id': 'f1', 'at': 'a1', 'to': 5},
    ]) {
      expect(InboundInner.fromJson(bad), isA<MalformedInner>(), reason: '$bad');
    }
  });

  test('unknown inner kind degrades gracefully', () {
    expect(
      InboundInner.fromJson(<String, dynamic>{'k': 'wat'}),
      isA<UnknownInner>(),
    );
  });
}
