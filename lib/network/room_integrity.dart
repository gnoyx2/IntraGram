import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:intragram/audit/merkle.dart';
import 'package:intragram/audit/signing.dart' show randomBytes;
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/protocol.dart'
    show wireBytes, wireId, wireInt;
import 'room_integrity/author_event.dart';

export 'room_integrity/author_event.dart';

part 'room_integrity/observation.dart';
part 'room_integrity/checkpoints.dart';
part 'room_integrity/seen_counters.dart';

// 남이 보낸 작성자 서명을 하나 이상 검증했고 체크포인트도 봤으면 verified. 위조·같은 번호의 다른 글·서명 뗀 글·
// 상충 체크포인트를 보면 conflict
enum RoomIntegrityStatus { waiting, verified, conflict }

// RAM 전용 방 관측 장부. 합의 원장이 아니라 이 기기가 본 것만 맞춰 봄: 방마다 최근 256개 사건·체크포인트만 남겨서
// 그보다 오래된 상충은 못 봄 (더 길게 보려면 감사 로그를 밖으로 반출해야 함)
final class RoomIntegrityBook extends ChangeNotifier {
  static const window = 256;
  final Map<String, _RoomObservation> _rooms = {};

  RoomIntegrityStatus status(String localId) {
    final room = _rooms[localId];
    if (room?.conflict ?? false) return RoomIntegrityStatus.conflict;
    return (room?.inbound ?? 0) > 0 && (room?.checkpointObserved ?? false)
        ? RoomIntegrityStatus.verified
        : RoomIntegrityStatus.waiting;
  }

  int retainedEvents(String localId) => _rooms[localId]?.events.length ?? 0;
  int retainedEnvelopes(String localId) =>
      _rooms[localId]?.authored.length ?? 0;
  int observedEvents(String localId) => _rooms[localId]?.observed ?? 0;
  String? scope(String localId) => _rooms[localId]?.scope;

  // 호스트 쪽: 처음 부를 때 무작위 범위를 정함
  String ensureRoom(String localId, {required String host}) =>
      (_rooms[localId] ??= _RoomObservation(newId(), host)).scope;

  void setMembers(String localId, Iterable<String> members) {
    final room = _rooms[localId];
    if (room == null) return;
    room.members
      ..clear()
      ..addAll(members.take(window));
  }

  // 멤버 쪽: 호스트 링크로 온 room_join·room_state의 범위를 따름 (도중에 범위나 호스트가 바뀌면 상충)
  void join(
    String localId,
    String scope,
    Iterable<String> members, {
    required String host,
  }) {
    final room = _rooms[localId];
    if (room != null && (room.scope != scope || room.host != host)) {
      conflict(localId);
      return;
    }
    _rooms.putIfAbsent(localId, () => _RoomObservation(scope, host));
    setMembers(localId, members);
    notifyListeners();
  }

  void conflict(String localId) {
    final room = _rooms[localId];
    if (room == null || room.conflict) return;
    room.conflict = true;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> sign(
    String localId,
    AppIdentity identity,
    Map<String, dynamic> payload,
  ) async {
    final room = _rooms[localId];
    if (room == null || identity.publicKey == null) return payload;
    final id = payload['id'] as String;
    final token = room.beginSigning(id);
    final previous = room.signing;
    // 작성자 번호는 링크별 암호 큐와 따로 한 줄로 세움 (여러 링크로 동시에 보내도 번호·이전 해시가 안 꼬임)
    final result = previous.then((_) async {
      if (!identical(_rooms[localId], room) || !room.isSigning(id, token)) {
        return null;
      }
      var event = room.authored[id];
      if (event == null) {
        try {
          event = await RoomAuthorEvent.sign(
            identity,
            roomId: room.scope,
            hostPeerId: room.host,
            counter: ++room.counter,
            previousHash: room.previous,
            payload: payload,
          );
        } on Object {
          if (!identical(_rooms[localId], room)) return null;
          rethrow;
        }
        if (!identical(_rooms[localId], room) ||
            !room.isSigning(id, token) ||
            identity.peerId != event.peerId) {
          return null;
        }
        if (!_record(room, event)) return null;
        room.previous = event.hash;
        room.authored[id] = event;
        _trim(room.authored);
        notifyListeners();
      }
      return <String, dynamic>{...payload, ...event.toWire()};
    });
    room.signing = result.then((_) {}, onError: (_) {});
    return result.whenComplete(() => room.endSigning(id, token));
  }

  Future<bool> observe(
    String localId,
    Map<String, dynamic> payload, {
    required String actorId,
  }) async {
    final room = _rooms[localId];
    final hasEnvelope = roomAuthorKeys.any(payload.containsKey);
    if (!hasEnvelope) {
      // 봉투 없는 옛 앱 글은 받음 (검증 배지만 안 오름). 단 이 방에서 이미 서명한 작성자 이름이면 중계가 서명을 뗀 것.
      // 작성자의 첫 서명 글을 보기 전에 떼인 글은 못 가려냄
      if (room == null || !room.signers.contains(actorId)) return true;
      conflict(localId);
      return false;
    }
    // 범위를 모르는 방(나가는 중·소각 직후)의 봉투 글은 맞춰 볼 게 없어서 버림
    if (room == null) return false;
    final event = RoomAuthorEvent.fromWire(payload, hostPeerId: room.host);
    if (event == null ||
        event.roomId != room.scope ||
        event.peerId != actorId ||
        !room.members.contains(event.peerId) ||
        !await event.verify(payload)) {
      conflict(localId);
      return false;
    }
    if (!identical(_rooms[localId], room)) return false;
    final key = '${event.peerId}:${event.counter}';
    final old = room.events[key];
    final predecessor = room.events['${event.peerId}:${event.counter - 1}'];
    final successor = room.events['${event.peerId}:${event.counter + 1}'];
    if ((event.counter == 1 &&
            event.previousHash != base64.encode(Uint8List(32))) ||
        (old != null && old.hash != event.hash) ||
        (predecessor != null && predecessor.hash != event.previousHash) ||
        (successor != null && successor.previousHash != event.hash)) {
      conflict(localId);
      return false;
    }
    // 상세 사건을 256개 창 밖에서 버려도 같은 서명 번호는 방이 살아 있는 동안 다시 받지 않음.
    if (!_record(room, event)) return false;
    room.inbound++;
    room.signers.add(event.peerId);
    while (room.signers.length > window) {
      room.signers.remove(room.signers.first);
    }
    notifyListeners();
    return true;
  }

  bool _record(_RoomObservation room, RoomAuthorEvent event) {
    final key = '${event.peerId}:${event.counter}';
    if (!room.seen.add(event.peerId, event.counter)) return false;
    // 원문 추측에 쓸 salt·커밋먼트·서명 봉투는 장부에 보관하지 않음.
    room.events[key] = _ObservedAuthorEvent(event.hash, event.previousHash);
    room.observed++;
    _trim(room.events);
    return true;
  }

  Map<String, dynamic> checkpoint(String localId) => _checkpoint(localId);

  bool observeCheckpoint(
    String localId,
    Map<String, dynamic> wire, {
    required String observerId,
  }) {
    final accepted = _observeCheckpoint(localId, wire, observerId: observerId);
    if (accepted) notifyListeners();
    return accepted;
  }

  void _trim<T>(Map<String, T> values) {
    while (values.length > window) {
      values.remove(values.keys.first);
    }
  }

  // 소각 직후 재전송 캐시에 남은 본문 커밋먼트 봉투도 퇴역시킴. 사건 해시·번호는 재생 차단용으로 유지.
  void retireMessage(String localId, String messageId) {
    final room = _rooms[localId];
    room?.authored.remove(messageId);
    room?.pending.remove(messageId);
  }

  void remove(String localId) {
    if (_rooms.remove(localId) != null) notifyListeners();
  }

  void clear() {
    _rooms.clear();
    notifyListeners();
  }
}
