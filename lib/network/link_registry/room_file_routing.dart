part of '../link_registry.dart';

// 한 발신자가 쥘 수 있는 미완료 경로 상한: 넘으면 그 발신자의 가장 오래된
// 경로부터 버림 (끝내 안 받은 옛 offer가 새 offer를 막지 않게,
// 한 멤버가 경로를 독식하지도 못하게). 수백 개 파일 폴더를 여러 멤버에게 한 번에 보내도 진행 중인 경로가 안 잘리게 넉넉히 둠
// (경로 하나는 링크 참조 둘뿐이라 이 상한에서도 메모리는 수 MB)
const int _kMaxRoomFileRoutesPerSender = 16384;

// 재접속 때 링크만 갈아 끼워도 같은 offer인지 식별할 수 있어야 함. 비동기 전달이 뒤늦게 실패하면 새 링크로 인계된 경로도 지우되,
// 그 사이 새 offer가 만든 경로는 건드리지 않음
class _RoomFileRoute {
  _RoomFileRoute(this.sender, this.target);
  PeerLink sender;
  PeerLink target;
}

// 방 안 파일 협상 프레임(offer/accept/reject/cancel/received/retry)의
// 대상별 중계 (호스트만). 바이트는 호스트를 안 거치고 수신자가 원본 멤버 서버에서 직접 당김
// - offer: 발신자가 to로 지정한 멤버 한 명에게만 넘기고 (전송 id, attempt)의 발신자<->대상 링크 쌍을 경로로 등록.
// 대상이 없거나/자기 자신이거나/전달 실패면 발신자에게 file_unavailable로 알림 (안 알리면 영영 offered로 기다림)
// - accept/reject/received/retry는 그 경로의 대상 링크가 보낸 것만 발신자에게 넘기고, cancel은
// 양쪽에서 반대편으로. 마지막 프레임(reject/received/cancel)은 전달 전에 경로부터 지움
// - 넘긴 결과는 항상 봄: 실패(false/봉인 예외)는 받을 링크를 닫아 링크 종료 정리가 전송을 실패로 돌리게 함
// - 경로에 없는 (id, attempt), 다른 멤버, 낡은 attempt의 프레임은 중계도 상태 변경도 안 함
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
    // 결과를 봄: 못 나갔으면(false/예외) 받을 링크를 닫아 링크 종료 정리가 전송을 실패로 돌리게 함
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
    // 같은 peerId 링크가 둘이면(재접속 직후 옛 링크가 아직 안 닫힘) 가장 최근 링크
    final target = _roomLinks.lastWhereOrNull(
      (link) =>
          link.conversationId == from.conversationId &&
          !link.isClosed &&
          link.remotePeerId == targetId,
    );
    // 대상이 방에 없으면(막 나간 멤버) 못 넘김: 곧 오는 명단 갱신에 맡기지
    // 않고 바로 알림 (그 갱신이 발신자의 수신자 등록보다 먼저 왔으면 놓침)
    // 자기 자신에게 보내는 offer도 같음
    if (target == null || identical(target, from)) {
      unawaited(
        from.sendFileUnavailable(id, attemptId: attempt, targetId: targetId),
      );
      return;
    }
    final key = (id, attempt);
    if (_conflictsWithRoomRoute(from, target, id, attempt)) {
      // 남의 경로를 가로채거나 남이 쓰는 전송 id를 선점하려는 offer: 중계 안 하고 그 발신자에게 접힘을 알림
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
    // 못 넘겼거나(false) 던졌으면(열린 링크의 봉인 오류 포함, 둘 다
    // 미전달) 대상은 이 offer를 못 봤으니 경로를 남기지 않고 발신자에게
    // 알림
    // (던진 것은 deliverRawInner가 미전달로 돌려줌)
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

  // closed 링크가 닫히면서 그 링크가 맡던 경로를 정리함. 같은 멤버의
  // 다른 열린 링크 survivor가 있으면(재접속 직후 옛 링크가 뒤늦게 닫힘)
  // 경로를 그쪽으로 넘겨 진행 중 전송이 이어지게 하고, 없으면 지움. 대상이 나갔으면 명단 갱신과 별도로 발신자에게 직접 실패를 알림
  // (명단 프레임이 누락돼도 offered 상태에 갇히지 않음)
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

  // from이 target에게 내는 (id, attempt) offer가 다른 경로와
  // 부딪히는가: 남의 경로를 가로채거나, 다른 멤버가 쓰는 전송 id를 쓰려는 경우
  // (다른 멤버가 남의 전송 id로 먼저 offer해 수신자가 그 id를 자기에게 묶게 만드는
  // 선점을 막음). 호스트가 그 id의 기록을 이미 갖고 있으면 인가 단계가 같은 검사를 함
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

  // sender의 경로가 상한이면 그 발신자의 가장 오래된 경로부터 버리고 그 수신자 몫이 접혔다고 알림
  // (밀려난 경로는 accept/ACK를 못 넘겨서, 안 알리면 발신자가 그 수신자를 영영 기다리거나 ACK 타임아웃까지 감)
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
