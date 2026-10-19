part of '../protocol.dart';

// 릴레이가 붙인 발신자 표기: from은 표시용 alias, peerId는 _PeerLinkAuthorization이 확정한 발신자
// (인증된 링크 신원 또는 신뢰된 호스트가 도장 찍은 값). 신뢰/수신자 판단엔 이 값만 씀
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
  });
  final String id;

  // 이 offer의 불투명 시도 id (AEAD AAD와 GET/POST 토큰이 여기 묶임)
  final String attempt;

  // push 또는 pull (파서가 이 둘 외 값은 프레임째 거부)
  final String mode;
  final String name;
  final int size;
  final String? mime;

  // pull 제안이면 원본 기기의 사설 IPv4 + 서버 포트 (파서가 RFC1918 정규 형식을 검증). push면 null
  final String? srcHost;
  final int? srcPort;

  // 이미지 제안이면 다운스케일 PNG의 base64 (수락 전 미리보기용)
  final String? thumb;

  // 스필된 긴 텍스트 제안의 앞부분 평문 스니펫. thumb과 배타적
  final String? preview;

  // 음성 메시지 제안이면 true: 받는 쪽이 자동 수락 + RAM 재생
  final bool voice;

  // 바이트가 보내는 쪽 링크의 파일 전송 서브키로 봉인됐는지 (1:1만, 그룹 방 직접 pull엔 공유 키가 없어 항상 false)
  final bool enc;

  // 같은 배치의 파일들이 공유하는 불투명 id. 단일 파일이면 null
  final String? batchId;

  // 보내는 쪽의 자기파괴 타이머(초). 0이면 꺼짐 (MessageInner.ttlSeconds와 같은 뜻)
  final int ttlSeconds;

  // pull일 때만 옴: offer를 낸 쪽의 GET /api/download/<id>
  // 인가 토큰 (파서가 pull이면 필수, push면 없어야 함으로 강제)
  final String? token;

  final String? from;
  final String? peerId;
  final String? to;

  // 봉인 안 된(방) 전송 내용의 SHA-256 base64 (파서가 32바이트를 확인). 받은 바이트가 다르면 지움
  final String? digest;
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

  // 수락하는 offer의 시도 id. 보내는 쪽은 자기가 아는 현재 attempt와 일치할 때만 처리
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

// 진행 중이거나 수락 전인 전송을 무름 (양방향). attempt는 무르는 시도라 다른 시도의 취소가 새 시도를 못 끊음
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

// 받는 쪽이 전송을 완전히 받아서 확인했다는 ACK
class FileReceivedInner extends InboundInner {
  const FileReceivedInner({
    required this.id,
    required this.attempt,
    this.from,
    this.peerId,
  });
  final String id;

  // 받는 쪽이 실제로 받은 시도. sender는 자기가 아는 그 recipient의 현재 attempt와 일치할 때만 완료 처리
  final String attempt;
  final String? from;
  final String? peerId;
}

// 호스트가 보낸 "target 수신자에게 (id, attempt)의 offer를
// 못 넘김" 통지: 발신자가 그 수신자 몫만 재시도 가능한 실패로 돌리게 함
// 수신자가 직접 무른 FileCancelInner와 달리 호스트가 만든 프레임이라 발신자
// 필드(from/pid)가 없고, 인가는 이 링크 상대가 확정된 방 호스트인지로만 판단
class FileUnavailableInner extends InboundInner {
  const FileUnavailableInner({
    required this.id,
    required this.attempt,
    required this.target,
  });
  final String id;
  final String attempt;

  // offer를 못 받은 수신자의 peerId (발신자의 수신자 키)
  final String target;
}

// 받는 쪽이 실패한 전송(attempt)을 다시 받고 싶다는 요청: 옛 토큰을
// 재사용하지 않고 보내는 쪽이 새 attempt/토큰으로 다시 offer하게 함
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
