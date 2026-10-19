part of 'outgoing_transfers.dart';

Future<void> _runOffer(
  OutgoingTransfers self, {
  required String conversationId,
  required String name,
  required String? path,
  required int size,
  required Stream<List<int>> Function() openStream,
  required String? batchLabel,
  String? batchId,
  String? mime,
  Future<String?> Function()? thumbFactory,
  String? preview,
  bool voice = false,
  Uint8List? selfBytes,
  Future<void> Function()? releaseSource,
}) async {
  final conversation = self.store.conversation(conversationId);
  if (conversation == null || self._closed) {
    // 아무도 이 제안을 안 맡게 됨(대화가 사라졌거나 세션이 이미 닫힘): 넘겨받은
    // native 자원을 여기서 놓지 않으면 새 세션이 끝날 때까지 새어 있음
    final orphan = OutgoingFileSource(
      conversationId: conversationId,
      name: name,
      size: size,
      openStream: openStream,
      host: null,
      port: null,
      encrypted: false,
      mode: FileTransferMode.push,
      spec: const OutgoingOfferSpec(),
      releaseSource: releaseSource,
    );
    await self._releaseSource(orphan);
    return;
  }

  final resolvedMime = mime ?? _mimeFor(name);
  final transferId = newId();
  final firstAttemptId = newId();

  // 그룹 방 제안 + 음성 메시지: 받는 쪽이 호스트를 안 거치고 여기서 바이트를 직접 당김. 제안에 이 기기 서버 주소를 도장 찍음
  // 서버가 꺼져 있으면 도장 없이 push로 나가고 (방이면 받는 쪽이
  // 못 당겨서 relay가 버림), 평범한 1:1 파일이면 항상 push
  final endpoint = (conversation.isRoom || voice)
      ? self._localEndpoint?.call()
      : null;
  final mode = conversation.isRoom || endpoint != null
      ? FileTransferMode.pull
      : FileTransferMode.push;

  // 1:1은 항상 암호화 대상으로 스테이징: 그룹 방만 예외 (멤버끼리 직접 pull이라 둘 사이 공유 키가 없어서 항상 평문
  // 호스트가 방 내용을 봐도 파일 바이트는 원래도 호스트를 안 거침)
  final encrypt = !conversation.isRoom;

  final source = OutgoingFileSource(
    conversationId: conversationId,
    name: name,
    size: size,
    openStream: openStream,
    host: conversation.peerHost,
    port: conversation.peerPort,
    encrypted: encrypt,
    mode: mode,
    spec: OutgoingOfferSpec(
      mime: resolvedMime,
      preview: preview,
      voice: voice,
      batchId: batchId,
      ttlSeconds: conversation.outgoingTtlSeconds,
    ),
    room: conversation.isRoom,
    viaRelayHost: conversation.isRoom && conversation.hostAlias != null,
    releaseSource: releaseSource,
  );
  self._outgoing[transferId] = source;

  self.store.upsertTransfer(
    FileTransfer(
      id: transferId,
      conversationId: conversationId,
      direction: TransferDirection.outgoing,
      fileName: name,
      totalBytes: size,
      mimeType: resolvedMime,
      localPath: path,
      state: TransferState.offered,
      batchLabel: batchLabel,
      batchId: batchId,
      voice: voice,
      encrypted: encrypt,
      attemptId: firstAttemptId,
      mode: mode,
      // 보낸 사람도 자기 음성 메시지를 들을 수 있어야 함: RAM에 이미
      // 있던 바이트를 내 쪽 기록에도 붙임 (전송 상태와 무관하게 즉시 재생
      // 가능)
      voiceBytes: voice ? selfBytes : null,
    ),
  );
  self.store.addMessage(
    EphemeralMessage(
      // transferId를 그대로 메시지 id로 씀: 양쪽이 같은 id를 써야 읽음 영수증/burn이 상대 쪽 메시지와 정확히 매칭됨
      id: transferId,
      conversationId: conversationId,
      direction: MessageDirection.outgoing,
      kind: MessageKind.file,
      senderAlias: self.identity.alias,
      createdAt: DateTime.now(),
      transferId: transferId,
      ttlSeconds: conversation.outgoingTtlSeconds,
      // 실제 진행은 TransferTile이 FileTransfer.state로 따로 그림. 이 필드는 정직하게 sending으로 시작
      delivery: DeliveryState.sending,
    ),
  );

  // 썸네일은 호출부가 아니라 로컬 행이 이미 뜬 지금 만듦: 호출부에서
  // 미리 await하면 이미지 디코드가 끝날 때까지 내 쪽 행이 안 떴음
  final thumb = await thumbFactory?.call();
  // 썸네일을 만드는 사이 소각/teardown이 이 source를 이미 치웠으면(그쪽이
  // native 자원도 놓음) 죽은 전송에 offer를 안 보냄
  if (self._closed || !identical(self._outgoing[transferId], source)) return;
  source.spec = OutgoingOfferSpec(
    mime: resolvedMime,
    thumb: thumb,
    preview: preview,
    voice: voice,
    batchId: batchId,
    ttlSeconds: conversation.outgoingTtlSeconds,
  );

  final links = self._linksForTransfer(conversationId);
  if (links.isEmpty) {
    // 대상이 하나도 없음(1:1 상대 오프라인, 방에 아무도 안 붙음):
    // 정직하게 실패로 보여줌. source는 남겨서 나중에 재시도할 수
    // 있게 함
    _failOffer(self, transferId);
    return;
  }
  await _offerToLinks(
    self,
    transferId,
    source,
    links,
    endpoint: endpoint,
    firstAttemptId: firstAttemptId,
  );
}

// links 각각을 수신자로 등록하고 각자 attempt/토큰으로 따로 offer (1:1이든 그룹이든
// 같은 경로). pull이면 수신자마다 자기 토큰을 발급해 한 수신자의 토큰을 다른 수신자가 재사용 못
// 함. 방 멤버로서 내는 offer는 호스트 링크 하나로 수신자별 라우팅 (_offerViaRelayHost)
// offer를 링크에 못 실은 수신자는 그 자리에서 실패로 기록 (offered로 남겨 성공한 척하지 않음)
Future<void> _offerToLinks(
  OutgoingTransfers self,
  String transferId,
  OutgoingFileSource source,
  List<PeerLink> links, {
  required ({String host, int port})? endpoint,
  String? firstAttemptId,
}) async {
  if (source.mode == FileTransferMode.pull && endpoint == null) {
    _failOffer(self, transferId);
    return;
  }
  if (!await _stampDigest(self, transferId, source)) return;
  if (source.viaRelayHost) {
    await self._offerViaRelayHost(
      transferId,
      source,
      endpoint: endpoint,
      firstAttemptId: firstAttemptId,
    );
    return;
  }
  var first = true;
  var undelivered = false;
  for (final link in links) {
    final key = recipientKeyOf(link);
    final recipient = _OutgoingRecipient(
      key: key,
      attemptId: first ? (firstAttemptId ?? newId()) : newId(),
      pullToken: source.mode == FileTransferMode.pull
          ? generateSecureToken()
          : null,
    );
    first = false;
    source._recipients[key] = recipient;
    final sent = await _sendOffer(
      source,
      link,
      transferId,
      recipient,
      endpoint: endpoint,
    );
    if (!sent) {
      recipient.fail();
      undelivered = true;
    }
  }
  if (undelivered) self._syncTransfer(transferId);
}

// 보낼 곳이 없어 실패로 표시: source는 남겨서 나중에 재시도할 수 있게 함
void _failOffer(OutgoingTransfers self, String transferId) =>
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.failed, error: 'network'),
    );

// recipient 한 명에게 현재 attempt/토큰으로 file_offer를 보냄. 링크로 내보내지 못하면 false
Future<bool> _sendOffer(
  OutgoingFileSource source,
  PeerLink link,
  String transferId,
  _OutgoingRecipient recipient, {
  required ({String host, int port})? endpoint,
}) => link.sendFileOffer(
  transferId: transferId,
  attemptId: recipient.attemptId,
  mode: source.mode == FileTransferMode.pull ? 'pull' : 'push',
  name: source.name,
  size: source.size,
  mime: source.spec.mime,
  srcHost: endpoint?.host,
  srcPort: endpoint?.port,
  thumb: source.spec.thumb,
  preview: source.spec.preview,
  voice: source.spec.voice,
  enc: source.encrypted,
  batchId: source.spec.batchId,
  ttlSeconds: source.spec.ttlSeconds,
  pullToken: recipient.pullToken,
  to: source.viaRelayHost ? recipient.key : null,
  digest: source.spec.digest,
);
