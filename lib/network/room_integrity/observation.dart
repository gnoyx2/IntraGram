part of '../room_integrity.dart';

// 방 하나의 관측 상태 (RoomIntegrityBook만 씀)
final class _RoomObservation {
  _RoomObservation(this.scope, this.host);
  final String scope;

  // 이 방의 호스트 peerId (호스트면 나, 멤버면 인증된 호스트 링크 상대). 작성자 서명이 이 값에 묶임
  final String host;
  final Map<String, _ObservedAuthorEvent> events = {};
  final _SeenAuthorCounters seen = _SeenAuthorCounters();
  final Map<String, RoomAuthorEvent> authored = {};
  final Map<String, Set<Object>> pending = {};
  final Map<String, String> checkpoints = {};
  final Set<String> members = {};

  // 이 방에서 서명 메시지를 1회 이상 전송한 작성자 집합임: 해당 peerId로 수신된 무서명 메시지는 호스트가 서명을 제거한 것으로 간주함
  final Set<String> signers = {};

  // 피어가 전송한 서명 메시지를 검증한 건수임 (본인 메시지 제외): 0건이면 검증 완료 상태로 판정하지 않음
  int inbound = 0;

  // 내 작성자 사슬은 무작위 번호에서 시작: 방을 나갔다 오거나 재잠금(신원은 그대로)으로 관측을 새로 열어도
  // 방이 아직 쥔 옛 번호를 다른 글에 다시 안 씀 (1부터 다시 세면 같은 번호의 다른 해시라 거짓 상충이 뜸)
  int counter = randomBytes(4).buffer.asByteData().getUint32(0);
  int observed = 0;
  String previous = base64.encode(Uint8List(32));
  bool conflict = false;
  bool checkpointObserved = false;
  Future<void> signing = Future.value();

  Object beginSigning(String id) {
    final token = Object();
    pending.putIfAbsent(id, () => <Object>{}).add(token);
    return token;
  }

  bool isSigning(String id, Object token) =>
      pending[id]?.contains(token) ?? false;

  void endSigning(String id, Object token) {
    final tokens = pending[id];
    tokens?.remove(token);
    if (tokens?.isEmpty ?? false) pending.remove(id);
  }
}

// 소각 이후에도 필요한 불투명한 사건 해시와 사슬 연결만 남김.
final class _ObservedAuthorEvent {
  const _ObservedAuthorEvent(this.hash, this.previousHash);
  final String hash;
  final String previousHash;
}
