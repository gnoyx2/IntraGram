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

  // SAS가 맞다고 내가 확인하면 보냄. 양쪽이 각자 보내야 검증 완료 (한쪽만이면 받는 쪽은 peerVerified만 켜짐)
  static Map<String, dynamic> verify() => <String, dynamic>{'k': 'verify'};

  // hello는 한 번뿐이라 연결된 상대는 이걸로만 새 이름을 앎. peerId가 바꾼 사람 것이라 방에서 그대로 중계돼도 누구 이름인지 앎
  static Map<String, dynamic> rename({
    required String alias,
    required String peerId,
  }) => <String, dynamic>{'k': 'rename', 'alias': alias, 'pid': peerId};

  static Map<String, dynamic> react({
    required String id,
    required String emoji,
    required bool on,
  }) => <String, dynamic>{'k': 'react', 'id': id, 'emoji': emoji, 'on': on};

  // 호스트 → 앱 멤버: 이 링크의 대화가 이제 호스트 중계 방. count는 이 멤버 포함 인원 (제목과 읽음 배지 분모에 씀)
  static Map<String, dynamic> roomJoin({
    required int count,
    List<String>? peers,
  }) => <String, dynamic>{'k': 'room_join', 'count': count, 'peers': ?peers};

  // 호스트 → 멤버 전원: 인원이 바뀜. joined/left는 시스템 메시지용 alias
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

  // 호스트 → 웹 게스트만: 포털 방이 꽉 차서 안 받고 닫음
  static Map<String, dynamic> roomFull() => <String, dynamic>{'k': 'room_full'};

  static Map<String, dynamic> burn(String id) => <String, dynamic>{
    'k': 'burn',
    'id': id,
  };

  static Map<String, dynamic> typing({required bool active}) =>
      <String, dynamic>{'k': 'typing', 'on': active};

  // 이 대화를 방금 스크린샷 찍었다고 알림 (감지만 됨, 차단은 못 함)
  static Map<String, dynamic> screenshot() => <String, dynamic>{
    'k': 'screenshot',
  };

  // sh/sp는 방과 음성 제안에 붙는 원본 서버 주소 (받는 쪽이 직접 당김). th(이미지 PNG)와 pv(긴 글 앞부분)는 같이 안 옴.
  // vc면 폴더 안 묻고 받아서 RAM 재생, ec면 파일 서브키로 봉인(1:1만). at는 시도 id, md는 push(보내는 쪽 POST)나
  // pull(받는 쪽 GET, 토큰 필요). dg는 봉인 안 된 방 전송의 SHA-256: 바이트는 평문으로 가도 offer는 인증된 링크로 가서 바꿔치기를 잡음
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
    String? senderPubKey,
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
    'sk': ?senderPubKey,
    if (voice) 'vc': true,
    if (enc) 'ec': true,
  };

  // token은 push 수신자가 새로 만든 32바이트 난수 (보내는 쪽이 POST 인가에 실음). 암호화된 링크로만 감 (1:1 전용)
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

  // 양쪽 다 씀. attempt가 있어서 옛 시도의 취소가 새 시도를 못 끊음
  static Map<String, dynamic> fileCancel(
    String id, {
    required String attempt,
  }) => <String, dynamic>{'k': 'file_cancel', 'id': id, 'at': attempt};

  // 실패한 시도를 다시 받고 싶다는 요청: 보내는 쪽이 새 attempt·토큰으로 다시 offer함
  static Map<String, dynamic> fileRetry(String id, {required String attempt}) =>
      <String, dynamic>{'k': 'file_retry', 'id': id, 'at': attempt};

  // 길이·AEAD 검증과 커밋(또는 RAM 이전)까지 끝난 뒤 한 번 보냄. attempt로 받은 시도를 못박아서 옛 시도의 늦은 ACK가 새 시도를 완료 못 시킴.
  // rc는 선택: 받는 쪽 신원 키로 서명한 수신 영수증 (옛 앱은 없이 보내고 받는 쪽도 없으면 ACK로만 씀)
  static Map<String, dynamic> fileReceived(
    String id, {
    required String attempt,
    Map<String, dynamic>? receipt,
  }) => <String, dynamic>{
    'k': 'file_received',
    'id': id,
    'at': attempt,
    'rc': ?receipt,
  };

  // 호스트만 보냄: 멤버가 낸 offer를 target에게 못 넘김 (방에 없음·자기 자신·전달 실패). file_cancel(수신자가 무름)과 달리
  // 네트워크 실패라 그 수신자 몫만 재시도 가능한 실패로 돌림. 확정된 방 호스트 것만 인가됨
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
