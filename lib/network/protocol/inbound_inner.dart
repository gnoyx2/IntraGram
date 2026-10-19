part of '../protocol.dart';

sealed class InboundInner {
  const InboundInner();

  // wire JSON을 typed 프레임으로 바꿈. 절대 안 던짐: 필수 필드가 없거나 형식/범위가 틀리면(0/빈 문자열 같은 기본값으로
  // 정상 프레임을 만들지 않고) MalformedInner를 돌려줌. 호출부(PeerLink)는
  // MalformedInner/UnknownInner면
  // local dispatch도 relay도 안 함. 실제 파싱은 protocol/parse_inner.dart
  factory InboundInner.fromJson(Map<String, dynamic> j) {
    try {
      return _parseInner(j);
    } on _BadField catch (e) {
      return MalformedInner('bad field "${e.field}" in "${j['k']}"');
    }
  }
}

// 필수 필드 누락/형식 오류로 typed 프레임이 될 수 없는 입력. 사유엔 필드 이름만 담고 값(토큰/경로 등)은 절대 안 담음
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

  // 릴레이가 붙인 발신자 alias (직접 링크에선 null)
  final String? from;

  // _PeerLinkAuthorization이 확정한 발신자 peerId (웹 게스트는 alias로
  // 대체). senderPeerId로 저장돼 reactions/readBy 키의 기준이 됨
  final String? peerId;
}

class AckInner extends InboundInner {
  const AckInner({required this.id});
  final String id;
}

class ReadInner extends InboundInner {
  const ReadInner({required this.id, this.from, this.peerId});
  final String id;

  // 릴레이가 붙인 발신자 alias (직접 링크에선 null)
  final String? from;

  // _PeerLinkAuthorization이 확정한 읽은 사람의 peerId (웹 게스트는 alias로 대체)
  final String? peerId;
}

class VerifyInner extends InboundInner {
  const VerifyInner();
}

class RenameInner extends InboundInner {
  const RenameInner({required this.alias, required this.peerId});
  final String alias;

  // 이름을 바꾼 사람의 peerId. 1:1이면 링크 상대(remotePeerId)와
  // 같지만, 방에서 호스트가 다른 멤버의 것을 그대로 중계하면 다를 수 있음
  // (멤버 맵에서 이 값으로 alias를 찾음)
  final String peerId;
}

class BurnInner extends InboundInner {
  const BurnInner({required this.id});
  final String id;
}

class ScreenshotInner extends InboundInner {
  const ScreenshotInner({this.from});

  // 릴레이가 붙인 발신자 alias (직접 링크에선 null)
  final String? from;
}

class TypingInner extends InboundInner {
  const TypingInner({required this.active, this.from});
  final bool active;

  // 릴레이가 붙인 발신자 alias (직접 링크에선 null)
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

  // true면 리액션 추가, false면 제거
  final bool on;

  // 릴레이가 붙인 발신자 alias (직접 링크에선 null)
  final String? from;

  // _PeerLinkAuthorization이 확정한 리액션 건 사람의
  // peerId (웹 게스트는 alias로 대체). reactions 맵의
  // 키
  final String? peerId;
}

class RoomJoinInner extends InboundInner {
  const RoomJoinInner({required this.count, this.peers = const []});

  // 이 멤버를 포함한 현재 방 인원. roomTitle로 표시 이름을 뽑고 memberCount로
  // 저장해서 room_state 없이도 읽음 카운트 배지가 바로 맞게 뜸
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

  // 호스트 포함 현재 방 인원
  final int count;

  // 방금 들어온/나간 사람의 alias (시스템 메시지용), 없으면 null
  final String? joined;
  final String? left;
  final List<String> peers;
}

class UnknownInner extends InboundInner {
  const UnknownInner({required this.kind});
  final String kind;
}
