part of '../link_registry.dart';

mixin _LinkRegistryFacade on _LinkRegistryState {
  // 양쪽 다 눌러야 확인 완료 (상대가 아직이면 UI는 '대기 중'). expectedSas는 대화상자에 띄웠던 코드: 그사이 재연결로 바뀌었으면 무시
  void markVerified(String conversationId, {required String? expectedSas}) {
    final conversation = store.conversation(conversationId);
    if (conversation == null || conversation.sas != expectedSas) return;
    final alreadyMutual = conversation.peerVerified;
    store.setLocalVerified(conversationId);
    store.addSystemMessage(
      conversationId,
      SystemEvent(
        alreadyMutual
            ? SystemEventKind.mutuallyVerified
            : SystemEventKind.markedVerified,
      ),
    );
    final link = _links[conversationId];
    if (link != null) unawaited(link.sendRawInnerOrClose(InnerFrame.verify()));
  }

  // markVerified의 방 멤버판: 대화 전체가 아니라 그 멤버 슬롯만 바꿈
  void markRoomMemberVerified(
    String conversationId,
    String peerId, {
    required String? expectedSas,
  }) {
    final member = store.conversation(conversationId)?.members[peerId];
    if (member == null || member.sas != expectedSas) return;
    final alreadyMutual = member.peerVerified;
    store.setRoomMemberLocalVerified(conversationId, peerId);
    store.addSystemMessage(
      conversationId,
      SystemEvent(
        alreadyMutual
            ? SystemEventKind.mutuallyVerified
            : SystemEventKind.markedVerified,
      ),
    );
    final link = _linkToMember(conversationId, peerId);
    if (link != null) unawaited(link.sendRawInnerOrClose(InnerFrame.verify()));
  }

  // 숫자가 다름(버튼이나 다른 코드 스캔): 중간자일 수 있어서 그 링크를 바로 닫고 경고 줄을 남김
  Future<void> reportSasMismatch(
    String conversationId, {
    String? memberPeerId,
  }) async {
    store.addSystemMessage(
      conversationId,
      const SystemEvent(SystemEventKind.sasMismatch),
    );
    // 재연결이 예전 확인을 이어 가지 않게 지움 (_carryVerification)
    store.clearVerified(conversationId);
    final link = memberPeerId == null
        ? _links[conversationId]
        : _linkToMember(conversationId, memberPeerId);
    await link?.close();
  }

  // 호스트면 그 멤버의 지금 링크만 봄 (재접속 직후엔 닫히는 중인 옛 링크가 아직 목록에 있음). 멤버면 호스트 링크 하나뿐
  PeerLink? _linkToMember(String conversationId, String peerId) =>
      _isRoomHub(conversationId)
      ? _memberLinks(
          conversationId,
        ).firstWhereOrNull((l) => l.remotePeerId == peerId)
      : _links[conversationId];

  // hello는 핸드셰이크 때 한 번뿐이라 이게 없으면 연결된 상대는 바뀐 이름을 못 봄
  void broadcastRename(String alias) {
    for (final link in <PeerLink>{..._links.values, ..._roomLinks}) {
      if (link.isClosed) continue;
      unawaited(
        link.sendRawInnerOrClose(
          InnerFrame.rename(alias: alias, peerId: identity.peerId),
        ),
      );
    }
  }

  // 확인 안 된 대화에선 무시: 중간자일 수 있어서 그 파일은 탭 없이는 안 떨어짐
  void setAutoAcceptFiles(String conversationId, {required bool enabled}) {
    final conversation = store.conversation(conversationId);
    if (conversation == null || !conversation.verified) return;
    store.setConversationAutoAccept(conversationId, value: enabled);
  }

  // 파일: TransferCoordinator로 넘기는 얇은 위임

  Future<void> offerFile(String conversationId, PlatformFile file) =>
      _transfers.outgoing.offerFile(conversationId, file);

  Future<void> offerFiles(String conversationId, List<PlatformFile> files) =>
      _transfers.outgoing.offerFiles(conversationId, files);

  Future<void> offerFilesFromPaths(String conversationId, List<String> paths) =>
      _transfers.outgoing.offerFilesFromPaths(conversationId, paths);

  // 모바일 첨부를 디스크 사본 없이 네이티브 스트림 그대로 제안. 소스 자원은 전송이 끝날 때 레지스트리가 놓고,
  // 도중에 실패하면 손도 못 댄 나머지는 여기서 놓음
  Future<void> offerStreamSources(
    String conversationId,
    List<MobileFileSource> sources,
  ) async {
    final batchId = sources.length > 1 ? newId() : null;
    var next = 0;
    try {
      for (; next < sources.length; next++) {
        final source = sources[next];
        await _transfers.outgoing.offerStreamSource(
          conversationId: conversationId,
          name: source.name,
          size: source.size,
          openStream: source.openRead,
          batchLabel: sources.length > 1
              ? '${next + 1} / ${sources.length}'
              : null,
          batchId: batchId,
          releaseSource: source.release,
        );
      }
    } on Object {
      // 던진 소스는 offerStreamSource가 맡음. 나머지만 여기서 놓음
      await MobileFileSource.releaseEach(sources.skip(next + 1));
      rethrow;
    }
  }

  // 붙여넣은 이미지·음성 메시지 같은 RAM 바이트를 파일로 제안 (디스크엔 안 씀)
  Future<void> offerInlineBytes(
    String conversationId,
    String name,
    Uint8List bytes, {
    String? mime,
    bool voice = false,
  }) => _transfers.outgoing.offerInlineBytes(
    conversationId,
    name,
    bytes,
    mime: mime,
    voice: voice,
  );

  Future<void> acceptTransfer(String transferId) =>
      _transfers.incoming.accept(transferId);

  Future<void> rejectTransfer(String transferId) =>
      _transfers.incoming.reject(transferId);

  Future<void> acceptBatch(String conversationId, String batchId) =>
      _transfers.incoming.acceptBatch(conversationId, batchId);

  Future<void> rejectBatch(String conversationId, String batchId) =>
      _transfers.incoming.rejectBatch(conversationId, batchId);

  void cancelTransfer(String transferId) {
    switch (store.transfer(transferId)?.direction) {
      case TransferDirection.outgoing:
        _transfers.outgoing.cancelTransfer(transferId);
      case TransferDirection.incoming:
        _transfers.incoming.cancelTransfer(transferId);
      case null:
        break;
    }
  }

  Future<void> retryTransfer(String transferId) async {
    switch (store.transfer(transferId)?.direction) {
      case TransferDirection.outgoing:
        await _transfers.outgoing.retryTransfer(transferId);
      case TransferDirection.incoming:
        await _transfers.incoming.retryTransfer(transferId);
      case null:
        break;
    }
  }

  // 테스트·진단용
  OutgoingFileSource? outgoingSource(String transferId) =>
      _transfers.outgoing.source(transferId);

  // GET /api/download/<id>: 토큰·attempt·선언 크기·상태를 다 확인한 뒤에만 그 수신자 토큰을 씀
  Future<OutgoingDownload?> openDownload({
    required String transferId,
    required String attemptId,
    required String token,
    required int declaredSize,
  }) => _transfers.outgoing.openDownload(
    transferId: transferId,
    attemptId: attemptId,
    token: token,
    declaredSize: declaredSize,
  );

  // attemptId·headerDeclaredSize는 서버가 헤더에서 이미 필수로 검사함
  Future<bool> receiveTransfer({
    required String transferId,
    required String attemptId,
    required String token,
    required Stream<List<int>> body,
    required int headerDeclaredSize,
  }) => _transfers.incoming.receive(
    transferId: transferId,
    attemptId: attemptId,
    token: token,
    body: body,
    headerDeclaredSize: headerDeclaredSize,
  );

  // 테스트가 링크 없이 accept → receive를 직접 몰 때만 씀
  @visibleForTesting
  IncomingTransfers get debugIncoming => _transfers.incoming;

  // debugIncoming의 보내는 쪽판
  @visibleForTesting
  OutgoingTransfers get debugOutgoing => _transfers.outgoing;

  // InMemoryStore.onTransferRemoved에서 불림 (app_providers가 이음)
  Future<void> discardRemovedTransfer(FileTransfer transfer) =>
      _transfers.discardTransfer(transfer);

  // 포털 끔: 웹 게스트 링크를 다 닫음 (토큰 폐기와 짝). 앱 그룹 방은 안 건드림
  Future<void> disconnectWebGuests() async {
    final guestRoomId = _webGuestRoomId;
    if (guestRoomId == null) return;
    final guests = _roomLinks
        .where((link) => link.conversationId == guestRoomId)
        .toList();
    for (final link in guests) {
      await link.close();
    }
  }
}
