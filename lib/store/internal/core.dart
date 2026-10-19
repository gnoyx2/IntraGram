part of '../in_memory_store.dart';

mixin _StoreCore on _InMemoryStoreState {
  List<Conversation> get conversations {
    final list = _conversations.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List<Conversation>.unmodifiable(list);
  }

  Conversation? conversation(String id) => _conversations[id];

  List<EphemeralMessage> messages(String conversationId) =>
      List<EphemeralMessage>.unmodifiable(
        _messages[conversationId]?.values ?? const <EphemeralMessage>[],
      );

  EphemeralMessage? messageById(String messageId) => _findMessage(messageId);

  Iterable<({String conversationId, EphemeralMessage message})> searchMessages(
    String query, {
    String? conversationId,
  }) sync* {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return;
    final rooms = conversationId != null
        ? <String>[conversationId]
        : _messages.keys.toList();
    for (final room in rooms) {
      for (final m in _messages[room]?.values ?? const <EphemeralMessage>[]) {
        if (m.kind != MessageKind.text || m.burned) continue;
        if ((m.text ?? '').toLowerCase().contains(needle)) {
          yield (conversationId: room, message: m);
        }
      }
    }
  }

  FileTransfer? transfer(String id) => _transfers[id];

  List<FileTransfer> get transfers =>
      List<FileTransfer>.unmodifiable(_transfers.values);

  List<FileTransfer> transfersInBatch(String conversationId, String batchId) =>
      _transfers.values
          .where(
            (t) => t.conversationId == conversationId && t.batchId == batchId,
          )
          .toList();

  Stream<List<Conversation>> watchConversations() async* {
    yield conversations;
    yield* _conversationEvents.stream;
  }

  Stream<List<EphemeralMessage>> watchRoom(String conversationId) async* {
    yield messages(conversationId);
    yield* _roomController(conversationId).stream;
  }

  Stream<List<FileTransfer>> watchTransfers() async* {
    yield transfers;
    yield* _transferEvents.stream;
  }

  // 타이머 걸린 메시지가 안 읽혀도 after 뒤엔 소각되게 함 (읽으면
  // _startBurn이 취소하고 ttlSeconds 카운트다운으로 넘김)
  void _armBurnCeiling(String messageId, Duration after) {
    if (_ceilingTimers.containsKey(messageId)) return;
    _ceilingTimers[messageId] = Timer(after, () {
      final m = _findMessage(messageId);
      if (m != null && !_localBurns.isClosed) {
        _localBurns.add((
          conversationId: m.conversationId,
          messageId: messageId,
        ));
      }
      burnMessage(messageId);
    });
  }

  EphemeralMessage? _findMessage(String messageId) =>
      _messages[_messageRooms[messageId]]?[messageId];

  // 방과 메시지를 바로 찾아 참조를 제거함
  void burnMessage(String messageId) {
    _burnTimers.remove(messageId)?.cancel();
    _ceilingTimers.remove(messageId)?.cancel();
    final roomId = _messageRooms.remove(messageId);
    final removed = _messages[roomId]?.remove(messageId);
    if (removed == null) return;
    _emitRoom(roomId!);
    final transferId = removed.transferId;
    if (transferId != null) _removeTransfer(transferId);
  }

  StreamController<List<EphemeralMessage>> _roomController(String id) =>
      _roomEvents.putIfAbsent(
        id,
        () => StreamController<List<EphemeralMessage>>.broadcast(),
      );

  void _emitConversations({bool persist = true}) {
    if (_conversationEvents.isClosed) return;
    _conversationEvents.add(conversations);
    if (persist) _schedulePersist();
  }

  void _emitRoom(String conversationId) {
    // 이 방을 보는 화면이 없어서 아래에서 조용히 return하더라도 방금 생긴 변경(타이머 만료, 원격 burn,
    // 닫힌 방 삭제 등)은 vault에 반영돼야 함. listener 확인 뒤에 두면 안 보는 방의 변경이 다음 실행까지 안 저장됨
    // (재실행하면 소각된 메시지가 부활한 것처럼 보임)
    _schedulePersist();
    final controller = _roomEvents[conversationId];
    if (controller == null || controller.isClosed) return;
    controller.add(messages(conversationId));
  }

  void _emitTransfers({bool persist = true}) {
    if (persist) _schedulePersist();
    if (_transferEvents.isClosed) return;
    _transferEvents.add(transfers);
  }

  // 전송 레코드를 스토어에서 떼고 화면에 즉시 반영한 뒤, 네트워크 정리(onTransferRemoved)와 owned 바이트 wipe를
  // 백그라운드 Future로 켬. burnMessage/wipeConversation/secureWipe가 전부 여길 거쳐서
  // "화면에서 없어짐"과 "실제로 정리됨"이 항상 같은 곳을 지남. 없는 id면 no-op
  void _removeTransfer(String id) {
    final transfer = _transfers.remove(id);
    if (transfer == null) return;
    OsPrivacy.evictImages(transfer.localPath);
    OsPrivacy.evictImages(transfer.thumbBytes);
    _emitTransfers();
    final future = _disposeTransfer(transfer);
    _pendingDisposals.add(future);
    // 정리 실패는 drainDisposals를 기다리는 쪽(패닉)이 보고함. 기다리는 쪽이 없어도
    // 미처리 async 에러로 새지 않게 여기서도 핸들러를 붙여 둠
    unawaited(
      future
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() => _pendingDisposals.remove(future)),
    );
  }

  // onTransferRemoved가 네트워크 자원을 놓을 때까지 기다린 뒤에만 owned voiceBytes를 지움
  // 순서가 반대면 아직 전송 중인 바이트를 먼저 지울 수 있음 (FileTransfer.voiceBytes의 공유 버퍼 설명 참고)
  Future<void> _disposeTransfer(FileTransfer transfer) async {
    try {
      await onTransferRemoved?.call(transfer);
    } finally {
      // 네트워크 정리가 실패해도 owned 바이트 wipe는 반드시 함. 실패는 전파돼 drainDisposals 쪽이 보고함
      final bytes = transfer.voiceBytes;
      if (bytes != null) SecureBytes.wipe(bytes);
    }
  }

  // 패닉 와이프만 부름 (일반 burn은 UI 반응성을 위해 fire-and-forget)
  Future<void> drainDisposals() => Future.wait(_pendingDisposals.toList());

  // 마지막 변경 1초 뒤 저장하되 연속 변경도 최대 5초만 기다림
  void _schedulePersist({Duration maxWait = const Duration(seconds: 5)}) {
    final hook = onPersistableChange;
    if (hook == null || _disposed) return;
    _saveDebounce?.cancel();
    void flush() {
      _saveDebounce?.cancel();
      _saveMaxWait?.cancel();
      _saveDebounce = _saveMaxWait = null;
      if (!_disposed) onPersistableChange?.call();
    }

    _saveMaxWait ??= Timer(maxWait, flush);
    _saveDebounce = Timer(const Duration(seconds: 1), flush);
  }
}
