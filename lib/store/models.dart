import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

part 'models/enums.dart';
part 'models/system_event.dart';
part 'models/ephemeral_message.dart';
part 'models/file_transfer.dart';
part 'models/peer_device.dart';
part 'models/conversation.dart';
part 'models/room_member.dart';

const MapEquality<String, Set<String>> _mapEq =
    MapEquality<String, Set<String>>(values: SetEquality<String>());
const SetEquality<String> _setEq = SetEquality<String>();
const MapEquality<String, RoomMember> _roomMembersEq =
    MapEquality<String, RoomMember>();

// 전부 깊게 불변이고 copyWith로만 갱신함. toJson/fromJson은 사용자가 켠 로컬 보관소(vault.dart)에서만 씀

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
