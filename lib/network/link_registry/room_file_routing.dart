part of '../link_registry.dart';

// 발신자당 미완료 경로 상한. 넘으면 그 발신자의 제일 오래된 것부터 버림 (안 받은 옛 offer가 새 걸 막거나 한 멤버가 독식 못 하게).
// 큰 폴더를 여러 멤버에게 보내도 안 잘리게 넉넉히 둠 (경로 하나는 링크 참조 둘이라 다 차도 수 MB)
const int _kMaxRoomFileRoutesPerSender = 16384;

// 가변인 이유: 재접속 때 링크만 갈아 끼움. 전달이 늦게 실패하면 identical로 그 경로인지 보고 지움 (그사이 새 offer가 만든 건 안 건드림)
class _RoomFileRoute {
  _RoomFileRoute(this.sender, this.target);
  PeerLink sender;
  PeerLink target;
}

// 방 파일 협상 프레임의 대상별 중계 (호스트만). offer는 to 한 명에게만 넘기고 (전송 id, attempt) 경로를 등록함.
// 대상이 없거나 자기 자신이거나 전달하지 못하면 발신자에게 file_unavailable을 보냄 (알리지 않으면 수신 대기 상태가 영구히 남음).
// accept·reject·received·retry는 그 경로 대상이 보낸 것만, cancel은 양쪽에서 반대편으로 전달함. 끝 프레임은 넘기기 전에 경로부터 지움.
// 경로에 없는 (id, attempt)나 다른 멤버 프레임은 중계도 상태 변경도 하지 않음
extension _RoomFileRouting on _LinkRegistryState {
  bool _canRouteRoomFileControl(
    PeerLink from,
    String kind,
    String id,
    String attempt,
  ) {
    final route = _roomFileRoutes[(id, attempt)];
    if (route == null ||
        route.sender.isClosed ||
        route.target.isClosed ||
        from.conversationId != route.sender.conversationId) {
      return false;
    }
    return identical(from, route.target) ||
        (kind == 'file_cancel' && identical(from, route.sender));
  }

  void _relayRoomFileFrame(PeerLink from, Map<String, dynamic> wire) {
    if (from.conversationId != _appRoomId) return;
    final kind = wire['k'];
    final id = wire['id'];
    final attempt = wire['at'];
    if (kind is! String || id is! String || attempt is! String) return;
    if (kind == 'file_offer') {
      unawaited(_routeRoomOffer(from, wire, id, attempt));
      return;
    }
    final key = (id, attempt);
    final route = _roomFileRoutes[key];
    if (route == null || !_canRouteRoomFileControl(from, kind, id, attempt)) {
      return;
    }
    final to = identical(from, route.target) ? route.sender : route.target;
    if (kind == 'file_received' ||
        kind == 'file_reject' ||
        kind == 'file_cancel') {
      _roomFileRoutes.remove(key);
    }
    // 못 나가면 받을 링크를 닫아서 링크 종료 정리가 전송을 실패로 돌림
    unawaited(to.sendRawInnerOrClose({...wire, 'from': from.peerAlias}));
  }

  Future<void> _routeRoomOffer(
    PeerLink from,
    Map<String, dynamic> wire,
    String id,
    String attempt,
  ) async {
    final targetId = wire['to'];
    if (targetId is! String || wire['sh'] != from.remoteHost) return;
    // 같은 peerId 링크가 둘이면(재접속 직후) 최신 링크를 씀
    final target = _roomLinks.lastWhereOrNull(
      (link) =>
          link.conversationId == from.conversationId &&
          !link.isClosed &&
          link.remotePeerId == targetId,
    );
    // 대상이 없거나(막 나감) 자기 자신이면 바로 알림: 명단 갱신에 맡기면 그게 발신자 등록보다 먼저 왔을 때 놓침
    if (target == null || identical(target, from)) {
      unawaited(
        from.sendFileUnavailable(id, attemptId: attempt, targetId: targetId),
      );
      return;
    }
    final key = (id, attempt);
    if (_conflictsWithRoomRoute(from, target, id, attempt)) {
      // 타인의 경로를 가로채거나 다른 멤버가 쓰는 id를 선점하려는 offer: 중계하지 않고 취소됨을 알림
      unawaited(
        from.sendOfferRefusal(id, attemptId: attempt, targetId: targetId),
      );
      return;
    }
    // 같은 전송을 같은 대상에게 다시 offer(재시도)하면 옛 attempt 경로는 버림
    _roomFileRoutes.removeWhere(
      (routeKey, route) =>
          routeKey.$1 == id &&
          identical(route.sender, from) &&
          identical(route.target, target),
    );
    _makeRoomForRoute(from);
    final route = _RoomFileRoute(from, target);
    _roomFileRoutes[key] = route;
    // 못 넘겼으면(봉인 오류 포함) 대상은 offer를 못 봤으니 경로를 지우고 발신자에게 알림
    if (!await target.deliverRawInner({...wire, 'from': from.peerAlias}) &&
        identical(_roomFileRoutes[key], route)) {
      _roomFileRoutes.remove(key);
      unawaited(
        route.sender.sendFileUnavailable(
          id,
          attemptId: attempt,
          targetId: targetId,
        ),
      );
    }
  }

  // 닫힌 링크가 맡던 경로 정리. survivor(같은 멤버의 새 링크)가 있으면 넘기고 없으면 지움.
  // 대상이 나갔으면 발신자에게 직접 알림 (명단 프레임을 놓쳐도 offered에 안 갇힘)
  void _handOverRoomFileRoutes(PeerLink closed, PeerLink? survivor) {
    for (final key in _roomFileRoutes.keys.toList()) {
      final route = _roomFileRoutes[key]!;
      final ownsSender = identical(route.sender, closed);
      final ownsTarget = identical(route.target, closed);
      if (!ownsSender && !ownsTarget) continue;
      if (survivor == null) {
        _roomFileRoutes.remove(key);
        final targetId = route.target.remotePeerId;
        if (ownsTarget && !ownsSender && targetId != null) {
          unawaited(
            route.sender.sendFileUnavailable(
              key.$1,
              attemptId: key.$2,
              targetId: targetId,
            ),
          );
        }
        continue;
      }
      if (ownsSender) route.sender = survivor;
      if (ownsTarget) route.target = survivor;
    }
  }

  // 남의 경로를 가로채거나 다른 멤버가 쓰는 전송 id를 쓰려는가 (남의 id로 먼저 offer해서 수신자가 그 id를 자기에게 묶게 하는 선점을 막음)
  bool _conflictsWithRoomRoute(
    PeerLink from,
    PeerLink target,
    String id,
    String attempt,
  ) {
    final old = _roomFileRoutes[(id, attempt)];
    if (old != null &&
        (!identical(old.sender, from) || !identical(old.target, target))) {
      return true;
    }
    return _roomFileRoutes.entries.any(
      (e) => e.key.$1 == id && e.value.sender.remotePeerId != from.remotePeerId,
    );
  }

  // 상한이면 그 발신자의 제일 오래된 경로를 버리고 취소됨을 알림 (안 알리면 수신 측이 영구히 대기 상태에 머묾)
  void _makeRoomForRoute(PeerLink sender) {
    if (_roomFileRoutes.length < _maxRoomFileRoutesPerSender) return;
    final own = <MapEntry<(String, String), _RoomFileRoute>>[
      for (final entry in _roomFileRoutes.entries)
        if (identical(entry.value.sender, sender)) entry,
    ];
    if (own.length < _maxRoomFileRoutesPerSender) return;
    final oldest = own.first;
    _roomFileRoutes.remove(oldest.key);
    final target = oldest.value.target;
    final targetId = target.remotePeerId;
    if (targetId == null) return;
    unawaited(
      sender.sendOfferRefusal(
        oldest.key.$1,
        attemptId: oldest.key.$2,
        targetId: targetId,
        targetAlias: target.peerAlias,
      ),
    );
  }
}
