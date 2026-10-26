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

  // 안 읽혀도 after 뒤엔 소각함 (읽으면 _startBurn이 넘겨받음)
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
      burnMessage(messageId, cause: BurnCause.unreadCeiling);
    });
  }

  EphemeralMessage? _findMessage(String messageId) =>
      _messages[_messageRooms[messageId]]?[messageId];

  // cause는 소각 증적에 남는 사유임 (상대 요청·사용자 삭제·타이머). 기본값은 내 기기에서만 지움
  void burnMessage(
    String messageId, {
    BurnCause cause = BurnCause.deletedForMe,
  }) {
    _burnTimers.remove(messageId)?.cancel();
    _ceilingTimers.remove(messageId)?.cancel();
    final roomId = _messageRooms[messageId];
    final doomed = _messages[roomId]?[messageId];
    // 지우기 직전에 커밋먼트를 잡음: 지운 뒤엔 localBurns로 id만 나가서 맥락이 없음
    final captured = doomed == null ? null : _attestBurn(this, doomed, cause);
    _messageRooms.remove(messageId);
    final removed = _messages[roomId]?.remove(messageId);
    if (removed == null) return;
    roomIntegrity.retireMessage(removed.conversationId, messageId);
    _emitRoom(roomId!);
    final transferId = removed.transferId;
    if (transferId != null) {
      _removeTransfer(transferId);
    } else if (captured != null) {
      _attestCleanup(
        this,
        done: Future<void>.value(),
        subjectId: removed.id,
        conversationId: removed.conversationId,
        policy: 'cleanup/message-reference',
        captured: captured,
      );
    }
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
    // 보는 화면이 없어 아래서 return해도 저장은 예약함 (안 그러면 안 보는 방의 소각이 저장 안 돼 재실행 때 되살아남)
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

  // 레코드를 떼고 화면에 바로 반영한 뒤 네트워크 정리와 바이트 덮기를 뒤에서 돌림. 소각·와이프가 전부 여길 지나서
  // '안 보임'과 '정리됨'이 한 길로 감. attest면 정리가 끝난 뒤 정리 증적을 남김 (secureWipe는 증적째 비워서 안 남김)
  Future<void> _removeTransfer(String id, {bool attest = true}) {
    final transfer = _transfers.remove(id);
    if (transfer == null) return Future<void>.value();
    OsPrivacy.evictImages(transfer.localPath);
    OsPrivacy.evictImages(transfer.thumbBytes);
    _emitTransfers();
    final generation = evidence.generation;
    final future = _disposeTransfer(transfer);
    _pendingDisposals.add(future);
    if (attest) {
      _attestCleanup(
        this,
        done: future,
        subjectId: transfer.id,
        conversationId: transfer.conversationId,
        transferId: transfer.id,
        policy: 'cleanup/transfer-resources',
        sinceGeneration: generation,
        attemptId: transfer.attemptId,
        counterpartId: _peerIdPattern.hasMatch(transfer.senderPeerId ?? '')
            ? transfer.senderPeerId
            : null,
        fields: <Object?>[
          transfer.id,
          transfer.direction.name,
          transfer.fileName,
          transfer.totalBytes,
          transfer.contentCommitment ?? transfer.digest ?? '',
        ],
      );
    }
    // 실패는 drainDisposals를 기다리는 패닉이 보고함. 기다리는 쪽이 없어도 처리 안 된 오류로 안 새게 핸들러를 붙임
    unawaited(
      future
          .then<void>((_) {}, onError: (Object _) {})
          .whenComplete(() => _pendingDisposals.remove(future)),
    );
    return future;
  }

  // 네트워크가 자원을 놓은 뒤에만 voiceBytes를 덮음 (거꾸로면 아직 보내는 중인 바이트를 지울 수 있음)
  Future<void> _disposeTransfer(FileTransfer transfer) async {
    try {
      await onTransferRemoved?.call(transfer);
    } finally {
      // 네트워크 정리가 실패해도 바이트는 꼭 덮음 (실패는 위로 감)
      final bytes = transfer.voiceBytes;
      if (bytes != null) SecureBytes.wipe(bytes);
    }
  }

  // 패닉만 부름
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
