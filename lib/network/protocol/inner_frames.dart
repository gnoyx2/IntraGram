part of '../protocol.dart';

class InnerFrame {
  const InnerFrame._();

  static Map<String, dynamic> message({
    required String id,
    required String text,
    required int ttlSeconds,
    required int timestampMs,
    String? replyToId,
  }) => <String, dynamic>{
    'k': 'msg',
    'id': id,
    'text': text,
    'ttl': ttlSeconds,
    'ts': timestampMs,
    're': ?replyToId,
  };

  static Map<String, dynamic> ack(String id) => {'k': 'ack', 'id': id};

  static Map<String, dynamic> read(String id) => <String, dynamic>{
    'k': 'read',
    'id': id,
  };

  // SAS 6자리가 맞다고 로컬에서 확인하면 보냄. 검증은 양쪽이 각자 보내야 완성됨
  // (한쪽만 보내면 받는 쪽은 peerVerified만 켜지고, 자기가 안 눌렀으면 여전히 미검증)
  static Map<String, dynamic> verify() => <String, dynamic>{'k': 'verify'};

  // hello는 핸드셰이크 때 한 번뿐이라 이미 연결된 피어는 이걸로만 새 이름을 앎. peerId는 이름을 바꾼 사람의 것이라
  // 방에서 호스트가 멤버 A의 rename을 B에게 맵 그대로 중계해도 B가 누구 이름인지 알 수 있음
  static Map<String, dynamic> rename({
    required String alias,
    required String peerId,
  }) => <String, dynamic>{'k': 'rename', 'alias': alias, 'pid': peerId};

  static Map<String, dynamic> react({
    required String id,
    required String emoji,
    required bool on,
  }) => <String, dynamic>{'k': 'react', 'id': id, 'emoji': emoji, 'on': on};

  // 호스트가 앱 멤버에게 보냄: 이 링크의 대화는 이제 호스트 중계 그룹 방
  // count는 이 멤버를 포함한 현재 방 인원이고 받는 쪽이 표시 이름 계산과 읽음 카운트 배지 분모로 씀
  static Map<String, dynamic> roomJoin({
    required int count,
    List<String>? peers,
  }) => <String, dynamic>{'k': 'room_join', 'count': count, 'peers': ?peers};

  // 호스트가 멤버 전원에게 보냄: 방 인원이 바뀜. joined/left는 시스템 메시지용 alias (둘 다 null이면 인원수만 갱신)
  static Map<String, dynamic> roomState({
    required int count,
    String? joined,
    String? left,
    List<String>? peers,
  }) => <String, dynamic>{
    'k': 'room_state',
    'count': count,
    'joined': ?joined,
    'left': ?left,
    'peers': ?peers,
  };

  // 호스트가 웹 게스트에게만 보냄: 포털 방이 꽉 차서 받지 않고 닫음
  static Map<String, dynamic> roomFull() => <String, dynamic>{'k': 'room_full'};

  static Map<String, dynamic> burn(String id) => <String, dynamic>{
    'k': 'burn',
    'id': id,
  };

  static Map<String, dynamic> typing({required bool active}) =>
      <String, dynamic>{'k': 'typing', 'on': active};

  // 이 대화의 스크린샷을 방금 찍었다고 피어에게 알림 (감지만 하고 차단은 못 함). payload 없음
  static Map<String, dynamic> screenshot() => <String, dynamic>{
    'k': 'screenshot',
  };

  // srcHost/srcPort는 그룹 방과 음성 제안에 붙음: 받는 쪽이 원본 서버에서
  // 직접 당길 주소. thumb(이미지 PNG base64)과 preview(스필된 긴 텍스트 앞부분)는
  // 배타적
  // voice면 받는 쪽이 폴더 선택 없이 자동 수락해 RAM에서 재생. enc면
  // 파일 전송 서브키로 봉인 (1:1만, 그룹 방 직접 pull은 항상 false)
  // attempt는 offer의 불투명 시도 id (AEAD AAD와 GET/POST 토큰이 묶임). mode는 push(보내는
  // 쪽이 POST) 또는 pull(받는 쪽이 GET, srcHost/srcPort 필요)이고 token은 pull일 때만 세팅
  // digest는 봉인 안 된(방) 전송 내용의 SHA-256 base64: 바이트는 평문으로 가도 이 offer는 인증된
  // 링크로 가서 받는 쪽이 LAN에서 바꿔치기된 내용을 잡음
  static Map<String, dynamic> fileOffer({
    required String id,
    required String attempt,
    required String mode,
    required String name,
    required int size,
    String? mime,
    String? srcHost,
    int? srcPort,
    String? thumb,
    String? preview,
    bool voice = false,
    bool enc = false,
    String? batchId,
    int ttlSeconds = 0,
    String? token,
    String? to,
    String? digest,
  }) => <String, dynamic>{
    'k': 'file_offer',
    'id': id,
    'at': attempt,
    'md': mode,
    'name': name,
    'size': size,
    'mime': ?mime,
    'sh': ?srcHost,
    'sp': ?srcPort,
    'th': ?thumb,
    'pv': ?preview,
    'bid': ?batchId,
    'ttl': ttlSeconds,
    'tok': ?token,
    'to': ?to,
    'dg': ?digest,
    if (voice) 'vc': true,
    if (enc) 'ec': true,
  };

  // attempt는 수락하는 offer의 시도 id, token은 push 수신자가 새로
  // 발급한 32바이트 보안 난수 (보내는 쪽이 POST /api/transfer 인가에 실음)
  // AEAD로 암호화된 이 링크로만 전달돼서 평문 relay보다 안전 (1:1 전용, 그룹 push는 없음)
  static Map<String, dynamic> fileAccept(
    String id, {
    required String attempt,
    required String token,
  }) => <String, dynamic>{
    'k': 'file_accept',
    'id': id,
    'at': attempt,
    'tok': token,
  };

  static Map<String, dynamic> fileReject(
    String id, {
    required String attempt,
  }) => <String, dynamic>{'k': 'file_reject', 'id': id, 'at': attempt};

  // 보내는 쪽/받는 쪽 둘 다 씀. attempt는 무르는 시도라 다른 시도의 취소가 새 시도를 못 끊음
  static Map<String, dynamic> fileCancel(
    String id, {
    required String attempt,
  }) => <String, dynamic>{'k': 'file_cancel', 'id': id, 'at': attempt};

  // 받는 쪽이 실패한 시도(attempt)를 다시 받고 싶다는 요청: 옛 토큰을
  // 재사용하지 않고 보내는 쪽이 새 attempt/토큰으로 다시 offer하게
  // 함
  static Map<String, dynamic> fileRetry(String id, {required String attempt}) =>
      <String, dynamic>{'k': 'file_retry', 'id': id, 'at': attempt};

  // 받는 쪽이 전송을 완전히 받아서(길이/AEAD 검증까지) 커밋 또는 RAM 소유권 이전을 마친 뒤 한 번 보냄
  // attempt로 그 recipient가 받은 시도를 못박아서 지난 attempt의 늦은 ACK가 새 시도를 완료시키지 않게 함
  static Map<String, dynamic> fileReceived(
    String id, {
    required String attempt,
  }) => <String, dynamic>{'k': 'file_received', 'id': id, 'at': attempt};

  // 호스트만 보냄: 방 멤버가 낸 (id, attempt)의 offer를
  // target 수신자에게 못 넘김 (방에 없음, 자기 자신, 전달 실패)
  // 수신자가 직접 무른 file_cancel과 달리 네트워크 실패라 받는 쪽은 그
  // 수신자 몫만 재시도 가능한 실패로 돌림 확정된 방 호스트가 보낸 것만 인가됨
  static Map<String, dynamic> fileUnavailable(
    String id, {
    required String attempt,
    required String target,
  }) => <String, dynamic>{
    'k': 'file_unavailable',
    'id': id,
    'at': attempt,
    'to': target,
  };
}
