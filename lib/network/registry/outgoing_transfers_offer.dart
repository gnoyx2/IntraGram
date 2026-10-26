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
    // 맡을 데가 없음(대화가 사라졌거나 세션이 닫힘): 받은 네이티브 자원을 여기서 안 놓으면 샘
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

  // 그룹 방 파일과 음성은 수신 측에서 직접 풀(pull) 방식으로 가져옴 (offer에 로컬 서버 주소를 포함함). 서버가 비활성화된 경우 음성은 push로,
  // 방 파일은 실패 처리됨. 일반 1:1 파일은 push 방식으로 전송함
  final endpoint = (conversation.isRoom || voice)
      ? self._localEndpoint?.call()
      : null;
  final mode = conversation.isRoom || endpoint != null
      ? FileTransferMode.pull
      : FileTransferMode.push;

  // 1:1 전송은 항상 암호화함. 그룹 방 파일만 평문임 (멤버 간 직접 수신하므로 상호 공유 키가 없음)
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
      // 보낸 사람도 자기 음성을 바로 들을 수 있게 RAM 바이트를 붙임
      voiceBytes: voice ? selfBytes : null,
    ),
  );
  self.store.addMessage(
    EphemeralMessage(
      // transferId를 메시지 id로: 양쪽 id가 같아야 읽음·소각이 상대 메시지와 맞음
      id: transferId,
      conversationId: conversationId,
      direction: MessageDirection.outgoing,
      kind: MessageKind.file,
      senderAlias: self.identity.alias,
      createdAt: DateTime.now(),
      transferId: transferId,
      ttlSeconds: conversation.outgoingTtlSeconds,
      // 진행은 전송 타일이 FileTransfer.state로 그림
      delivery: DeliveryState.sending,
    ),
  );

  // 썸네일은 내 쪽 행이 뜬 다음에 만듦 (먼저 만들면 디코드가 끝날 때까지 행이 안 뜸)
  final thumb = await thumbFactory?.call();
  // 그사이 데이터 소각이나 세션 정리가 발생했으면 종료된 전송에 offer를 발송하지 않음
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
    // 받을 사람이 없음(상대 오프라인, 빈 방): 실패로 보여 주고 source는 재시도용으로 남김
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

// 링크마다 수신자를 등록하고 개별 attempt 및 토큰으로 offer를 발송함 (pull 토큰은 수신자별로 분리 발급됨).
// 그룹 방 멤버로서 발신하는 offer는 호스트 링크로 중계함 (_offerViaRelayHost). 발송에 실패한 수신자는 즉시 실패 처리함
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

// 보낼 데가 없음: 실패로 두고 source는 재시도용으로 남김
void _failOffer(OutgoingTransfers self, String transferId) =>
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.failed, error: 'network'),
    );

// 개별 수신자에게 현재 attempt와 토큰으로 offer를 발송함. 발송 실패 시 false를 반환함
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
