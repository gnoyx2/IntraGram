part of '../room_integrity.dart';

extension _RoomCheckpoints on RoomIntegrityBook {
  Map<String, dynamic> _checkpoint(String localId) {
    final room = _rooms[localId];
    if (room == null) return const {};
    room.checkpointObserved = true;
    final keys = room.events.keys.toList()..sort();
    return {
      'roomIntegrityId': room.scope,
      'checkpointNo': room.observed,
      'merkleRoot': base64.encode(
        merkleRoot([
          for (final key in keys)
            merkleLeaf(const [], base64.decode(room.events[key]!.hash)),
        ]),
      ),
    };
  }

  bool _observeCheckpoint(
    String localId,
    Map<String, dynamic> wire, {
    required String observerId,
  }) {
    final room = _rooms[localId];
    if (room == null) return false;
    final no = wireInt(wire['checkpointNo'], min: 0, max: 9007199254740991);
    final root = wireBytes(wire['merkleRoot'], length: 32);
    if (no == null ||
        root == null ||
        wireId(wire['roomIntegrityId']) != room.scope) {
      conflict(localId);
      return false;
    }
    final key = '$observerId:$no';
    final hash = base64.encode(root);
    final prior = room.checkpoints[key];
    if (prior != null && prior != hash) {
      conflict(localId);
      return false;
    }
    room.checkpointObserved = true;
    room.checkpoints[key] = hash;
    _trim(room.checkpoints);
    return true;
  }
}
