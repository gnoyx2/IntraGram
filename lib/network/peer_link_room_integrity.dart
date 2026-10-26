part of 'peer_link.dart';

extension _PeerLinkRoomIntegrity on PeerLink {
  Future<bool> _verifyRoomIntegrity(_Authorized authorized) async {
    final wire = authorized.wire;
    final inner = authorized.inner;
    final book = store.roomIntegrity;
    if (inner is RoomJoinInner || inner is RoomStateInner) {
      final scope = wireId(wire['roomIntegrityId']);
      if (scope == null) {
        if (book.scope(conversationId) != null ||
            _checkpointKeys.any(wire.containsKey)) {
          book.ensureRoom(conversationId, host: remotePeerId!);
          book.conflict(conversationId);
          return false;
        }
        // 체크포인트를 모르는 옛 호스트
        return true;
      }
      final peers = inner is RoomJoinInner
          ? inner.peers
          : (inner as RoomStateInner).peers;
      book.join(conversationId, scope, peers, host: remotePeerId!);
      return book.observeCheckpoint(
        conversationId,
        wire,
        observerId: remotePeerId!,
      );
    }
    final conversation = store.conversation(conversationId);
    if (inner is! MessageInner || !(conversation?.isRoom ?? false)) return true;
    if (_roomRole == _RoomLinkRole.localHostMember) {
      book.ensureRoom(conversationId, host: identity.peerId);
      book.setMembers(conversationId, [
        identity.peerId,
        ...conversation!.members.keys,
      ]);
    }
    return book.observe(
      conversationId,
      wire,
      actorId: _resolveActor(inner.peerId),
    );
  }
}
