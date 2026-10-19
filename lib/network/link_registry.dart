import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'capped_socket.dart';
import 'crypto_engine.dart';
import 'peer_link.dart';
import 'protocol.dart';
import 'registry/incoming_transfers.dart';
import 'registry/outgoing_transfers.dart';
import 'registry/transfer_coordinator.dart';

export 'registry/transfer_coordinator.dart'
    show OutgoingFileSource, OutgoingDownload;

part 'link_registry/state.dart';
part 'link_registry/dial_error.dart';
part 'link_registry/room_broadcast.dart';
part 'link_registry/room.dart';
part 'link_registry/room_file_routing.dart';
part 'link_registry/room_roster.dart';
part 'link_registry/file_wiring.dart';
part 'link_registry/merge_duplicate.dart';
part 'link_registry/session.dart';
part 'link_registry/connect.dart';
part 'link_registry/inbound_guard.dart';
part 'link_registry/blocking.dart';
part 'link_registry/chat.dart';
part 'link_registry/facade.dart';
part 'link_registry/test_seams.dart';

// UI는 PeerLink를 직접 안 건드리고 레지스트리를 부름. 화면의 single source of truth는
// InMemoryStore이고, 파일 전송 메서드는 TransferCoordinator로 가는 얇은 delegate
// (호출자/테스트가 API 하나만 보게 여기 둠). 상태 필드는 _LinkRegistryState,
// 동작은 link_registry/의 믹스인
class LinkRegistry extends _LinkRegistryState
    with
        _LinkRegistryRoom,
        _LinkRegistryFileWiring,
        _LinkRegistryDuplicates,
        _LinkRegistrySession,
        _LinkRegistryConnect,
        _LinkRegistryChat,
        _LinkRegistryFacade,
        _LinkRegistryBlocking,
        _LinkRegistryTestSeams {
  // chooseDirectory는 수락한 파일의 저장 위치를 고르는 seam
  // (프로덕션은 null이라 플랫폼 로직이 돌고, 테스트는 임시 디렉토리 주입)
  // TransferCoordinator로 그대로 넘김
  LinkRegistry({
    required super.store,
    required super.crypto,
    required super.identity,
    super.chooseDirectory,
    super.ackTimeout,
  });
}
