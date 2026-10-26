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

// UI는 PeerLink 대신 이 객체를 호출함. 화면 상태의 정본은 InMemoryStore이고 파일 메서드는 TransferCoordinator로 넘기는 얇은 위임 레이어임
// (호출부·테스트가 API 하나만 보게 함). 상태는 _LinkRegistryState, 동작은 link_registry/ 믹스인으로 구성함
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
  // chooseDirectory: 받은 파일 저장 위치를 고르는 seam (프로덕션은 null이라 플랫폼 로직, 테스트는 임시 폴더)
  LinkRegistry({
    required super.store,
    required super.crypto,
    required super.identity,
    super.chooseDirectory,
    super.ackTimeout,
  });
}
