part of '../protocol.dart';

// from은 표시용 alias, peerId는 인가 단계가 확정한 발신자 (인증된 링크 신원이나 믿는 호스트의 도장). 신뢰·수신자 판단엔 peerId만 씀
class FileOfferInner extends InboundInner {
  const FileOfferInner({
    required this.id,
    required this.attempt,
    required this.mode,
    required this.name,
    required this.size,
    this.mime,
    this.srcHost,
    this.srcPort,
    this.thumb,
    this.preview,
    this.voice = false,
    this.enc = false,
    this.batchId,
    this.ttlSeconds = 0,
    this.token,
    this.from,
    this.peerId,
    this.to,
    this.digest,
    this.senderPubKey,
  });
  final String id;

  // 불투명 시도 id (AEAD AAD와 GET/POST 토큰이 여기 묶임)
  final String attempt;

  final String mode;
  final String name;
  final int size;
  final String? mime;

  // pull이면 원본 기기의 사설 IPv4 + 서버 포트 (파서가 정규 RFC 1918인지 봄). push면 null
  final String? srcHost;
  final int? srcPort;

  // 이미지면 줄인 PNG base64 (수락 전 미리보기)
  final String? thumb;

  // 긴 글 파일의 앞부분 미리보기. thumb과 같이 안 옴
  final String? preview;

  // 음성이면 받는 쪽이 자동 수락하고 RAM에서 재생
  final bool voice;

  // 보내는 쪽 링크의 파일 서브키로 봉인했는지 (1:1만, 방 직접 pull은 공유 키가 없어 늘 false)
  final bool enc;

  // 같은 묶음 파일들이 공유하는 id
  final String? batchId;

  // 자기파괴 타이머(초), 0이면 꺼짐
  final int ttlSeconds;

  // pull일 때만: GET /api/download/<id> 인가 토큰
  final String? token;

  final String? from;
  final String? peerId;
  final String? to;

  // 봉인 안 된(방) 전송 내용의 SHA-256 base64. 받은 바이트가 다르면 지움
  final String? digest;
  final String? senderPubKey;
}

class FileAcceptInner extends InboundInner {
  const FileAcceptInner({
    required this.id,
    required this.attempt,
    required this.token,
    this.from,
    this.peerId,
  });
  final String id;

  // 수락하는 offer의 시도 id. 보내는 쪽은 자기가 아는 지금 attempt와 같을 때만 처리
  final String attempt;

  // push 수신자가 발급한 POST /api/transfer 인가 토큰
  final String token;
  final String? from;
  final String? peerId;
}

class FileRejectInner extends InboundInner {
  const FileRejectInner({
    required this.id,
    required this.attempt,
    this.from,
    this.peerId,
  });
  final String id;
  final String attempt;
  final String? from;
  final String? peerId;
}

// 진행 중이거나 수락 전인 전송을 무름 (양방향). attempt가 있어서 옛 시도의 취소가 새 시도를 못 끊음
class FileCancelInner extends InboundInner {
  const FileCancelInner({
    required this.id,
    required this.attempt,
    this.from,
    this.peerId,
  });
  final String id;
  final String attempt;
  final String? from;
  final String? peerId;
}

// 받는 쪽이 다 받아서 확인했다는 ACK
class FileReceivedInner extends InboundInner {
  const FileReceivedInner({
    required this.id,
    required this.attempt,
    this.from,
    this.peerId,
    this.receipt,
  });
  final String id;

  // 받는 쪽이 실제로 받은 시도. 보내는 쪽은 그 수신자의 지금 attempt와 같을 때만 완료 처리
  final String attempt;
  final String? from;
  final String? peerId;

  // 선택: 받는 쪽이 서명한 수신 영수증 원본 (엄격 파싱·서명 검사는 보내는 쪽 증적 단계가 함)
  final Map<String, dynamic>? receipt;
}

// 호스트가 '수신자 target에게 이 offer를 못 넘김'을 알림: 발신자는 그 수신자 몫만 재시도 가능한 실패로 돌림.
// 호스트가 만든 프레임이라 from/pid가 없고, 링크 상대가 확정된 방 호스트인지로만 인가함
class FileUnavailableInner extends InboundInner {
  const FileUnavailableInner({
    required this.id,
    required this.attempt,
    required this.target,
  });
  final String id;
  final String attempt;

  // offer를 못 받은 수신자 peerId
  final String target;
}

// 실패한 시도를 다시 받고 싶다는 요청: 보내는 쪽이 옛 토큰 말고 새 attempt·토큰으로 다시 offer함
class FileRetryInner extends InboundInner {
  const FileRetryInner({
    required this.id,
    required this.attempt,
    this.from,
    this.peerId,
  });
  final String id;
  final String attempt;
  final String? from;
  final String? peerId;
}
