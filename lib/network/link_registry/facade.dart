part of '../link_registry.dart';

mixin _LinkRegistryFacade on _LinkRegistryState {
  // 검증은 양쪽 다 이걸 해야 완성됨: 피어가 아직 안 눌렀으면 Conversation.verified는
  // false로 남고 UI는 "대기중"으로 보여줌
  // expectedSas는 다이얼로그가 열렸을 때 보여준 SAS: 그 사이 재연결로 세션이 바뀌어 실제 sas가 달라졌으면 조용히 무시
  // (새 세션의 확인 결과로 잘못 적용되는 걸 막음)
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

  // 방 멤버 한 명에게 markVerified와 같은 걸 함 (대화 전체가 아니라 그
  // 멤버 슬롯만). 호스트는 _roomLinks에서 peerId로 그 멤버의 링크를
  // 찾고
  // 멤버는 링크가 하나뿐이라 _links에서 찾음. expectedSas는 markVerified와 같은 stale 방지용
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
    final link =
        _links[conversationId] ??
        _roomLinks.firstWhereOrNull((l) => l.remotePeerId == peerId);
    if (link != null) unawaited(link.sendRawInnerOrClose(InnerFrame.verify()));
  }

  // 사용자가 숫자가 다르다고 확인함(버튼 또는 다른 숫자의 코드 스캔): 중간자가 있을 수 있어
  // 그 상대와의 링크를 바로 닫고 경고 줄을 남김. 방이면 그 멤버 링크(호스트) 또는 호스트 링크(멤버)를 닫음
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
    final link =
        _links[conversationId] ??
        (memberPeerId == null
            ? null
            : _roomLinks.firstWhereOrNull(
                (l) => l.remotePeerId == memberPeerId,
              ));
    await link?.close();
  }

  // hello는 핸드셰이크 때 한 번뿐이라, 이미 연결된 피어는 이 호출 없인 이름을 바꿔도 예전 이름을 영영 못 봄
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

  // SAS로 검증 안 한 대화에선 무시: 검증 안 된 피어는 MITM일 수 있어서 그 파일은 탭 없이는 절대 안 떨어짐
  void setAutoAcceptFiles(String conversationId, {required bool enabled}) {
    final conversation = store.conversation(conversationId);
    if (conversation == null || !conversation.verified) return;
    store.setConversationAutoAccept(conversationId, value: enabled);
  }

  // 파일: TransferCoordinator의 두 절반으로 가는 얇은 delegate
  // (UI, 임베디드 서버, 테스트가 객체 하나와만 얘기하게 여기 둠)

  Future<void> offerFile(String conversationId, PlatformFile file) =>
      _transfers.outgoing.offerFile(conversationId, file);

  Future<void> offerFiles(String conversationId, List<PlatformFile> files) =>
      _transfers.outgoing.offerFiles(conversationId, files);

  Future<void> offerFilesFromPaths(String conversationId, List<String> paths) =>
      _transfers.outgoing.offerFilesFromPaths(conversationId, paths);

  // 모바일 zero-disk 첨부(MobileFileSource) 배치 제안: 디스크 사본 없이 네이티브 스트리밍 소스를 그대로 씀
  // 각 소스의 native 자원은 그 전송이 끝날 때 레지스트리가 놓고(releaseSource),
  // 배치 도중 실패하면 아직 손도 못 댄 나머지 소스를 여기서 놓음
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
      // 예외가 난 소스는 offerStreamSource가 맡음 (스테이징
      // 전이면 그 안에서 놓고, 후엔 레지스트리 몫). 나머지만 여기서
      await MobileFileSource.releaseEach(sources.skip(next + 1));
      rethrow;
    }
  }

  // 붙여넣은 이미지나 음성 메시지 같은 RAM 바이트 하나를 파일 제안으로 (보내는 쪽 디스크엔 안 씀)
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

  // backing source 조회 (테스트/진단용)
  OutgoingFileSource? outgoingSource(String transferId) =>
      _transfers.outgoing.source(transferId);

  // GET /api/download/<id> 인가 + AEAD wrapping. server_routes.dart가
  // outgoingSource를 직접 읽어 평문을 내보내던 경로를 대체함:
  // 토큰/attempt/선언 크기/현재 상태를 전부 검증한 뒤에만 그 수신자의 토큰을 소비
  // (자세한 건 OutgoingTransfersDownload.openDownload 참고)
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

  // attemptId/headerDeclaredSize는 서버가 헤더에서 이미 필수로 검사해서 넘김
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

  // 테스트가 살아 있는 PeerLink 없이 accept -> receive를 직접 호출할 때만
  // 씀. 객체를 그대로 넘겨 debugPushTokenFor 호출은 테스트 파일에서 일어나게
  // 함
  // (@visibleForTesting은 선언 라이브러리나 test/에서만 호출 가능해서 여기서 직접 부르면 lint 위반)
  @visibleForTesting
  IncomingTransfers get debugIncoming => _transfers.incoming;

  // debugIncoming의 아웃고잉판: 테스트가 EOF/ACK 결합 규칙을 직접 몰 때만 씀
  @visibleForTesting
  OutgoingTransfers get debugOutgoing => _transfers.outgoing;

  // InMemoryStore.onTransferRemoved가 부르는 진입점 (app_providers가
  // 연결). 자세한 건 TransferCoordinator.discardTransfer 참고
  Future<void> discardRemovedTransfer(FileTransfer transfer) =>
      _transfers.discardTransfer(transfer);

  // 포털 OFF: 붙어있는 웹 게스트 링크 전부 닫음 (토큰 폐기와 짝). 앱 그룹 방 멤버는 별개 방(_appRoomId)이라 안 건드림
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
