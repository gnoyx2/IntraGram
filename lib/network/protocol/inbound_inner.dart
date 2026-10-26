part of '../protocol.dart';

sealed class InboundInner {
  const InboundInner();

  // wire JSON을 타입 있는 프레임으로. 절대 안 던짐: 필드가 없거나 틀리면 MalformedInner라 호출부가 dispatch도 중계도 안 함.
  // from은 릴레이가 붙인 표시용 alias, peerId는 인가 단계가 확정한 발신자 (웹 게스트는 alias로 대신함)
  factory InboundInner.fromJson(Map<String, dynamic> j) {
    try {
      return _parseInner(j);
    } on _BadField catch (e) {
      return MalformedInner('bad field "${e.field}" in "${j['k']}"');
    }
  }
}

// typed 프레임이 될 수 없는 입력. 사유엔 필드 이름만 담고 값(토큰·경로)은 절대 안 담음
class MalformedInner extends InboundInner {
  const MalformedInner(this.reason);
  final String reason;
}

class MessageInner extends InboundInner {
  const MessageInner({
    required this.id,
    required this.text,
    required this.ttlSeconds,
    required this.timestampMs,
    this.replyToId,
    this.from,
    this.peerId,
  });
  final String id;
  final String text;
  final int ttlSeconds;
  final int timestampMs;

  final String? replyToId;

  final String? from;

  final String? peerId;
}

class AckInner extends InboundInner {
  const AckInner({required this.id});
  final String id;
}

class ReadInner extends InboundInner {
  const ReadInner({required this.id, this.from, this.peerId});
  final String id;

  final String? from;

  final String? peerId;
}

class VerifyInner extends InboundInner {
  const VerifyInner();
}

class RenameInner extends InboundInner {
  const RenameInner({required this.alias, required this.peerId});
  final String alias;

  // 이름 바꾼 사람의 peerId. 1:1이면 링크 상대와 같지만 방에선 호스트가 다른 멤버 것을 중계해서 다를 수 있음
  final String peerId;
}

class BurnInner extends InboundInner {
  const BurnInner({required this.id});
  final String id;
}

class ScreenshotInner extends InboundInner {
  const ScreenshotInner({this.from});

  final String? from;
}

class TypingInner extends InboundInner {
  const TypingInner({required this.active, this.from});
  final bool active;

  final String? from;
}

class ReactInner extends InboundInner {
  const ReactInner({
    required this.id,
    required this.emoji,
    required this.on,
    this.from,
    this.peerId,
  });

  final String id;
  final String emoji;

  final bool on;

  final String? from;

  final String? peerId;
}

class RoomJoinInner extends InboundInner {
  const RoomJoinInner({required this.count, this.peers = const []});

  // 이 멤버를 포함한 방 인원 (room_state 없이도 제목·읽음 배지가 바로 맞게)
  final int count;
  final List<String> peers;
}

class RoomStateInner extends InboundInner {
  const RoomStateInner({
    required this.count,
    this.joined,
    this.left,
    this.peers = const [],
  });

  // 호스트 포함 방 인원
  final int count;

  // 방금 들어오거나 나간 사람 alias (시스템 메시지용)
  final String? joined;
  final String? left;
  final List<String> peers;
}

class UnknownInner extends InboundInner {
  const UnknownInner({required this.kind});
  final String kind;
}
