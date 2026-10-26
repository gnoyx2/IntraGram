part of 'peer_link.dart';

extension PeerLinkOutboundFile on PeerLink {
  // to가 있으면 방 안 특정 멤버 몫 (호스트가 그 멤버에게만 중계). 못 내보내면 false
  Future<bool> sendFileOffer({
    required String transferId,
    required String attemptId,
    required String mode,
    required String name,
    required int size,
    String? mime,
    String? srcHost,
    int? srcPort,
    String? thumb,
    String? preview,
    bool voice = false,
    bool enc = false,
    String? batchId,
    int ttlSeconds = 0,
    String? pullToken,
    String? to,
    String? digest,
  }) => _sendInner(
    InnerFrame.fileOffer(
      id: transferId,
      attempt: attemptId,
      mode: mode,
      name: name,
      size: size,
      mime: mime,
      srcHost: srcHost,
      srcPort: srcPort,
      thumb: thumb,
      preview: preview,
      voice: voice,
      enc: enc,
      batchId: batchId,
      ttlSeconds: ttlSeconds,
      token: pullToken,
      to: to,
      digest: digest,
      senderPubKey: identity.publicKey == null
          ? null
          : base64.encode(identity.publicKey!),
    ),
  );

  // 호스트 전용: 멤버가 targetId에게 낸 offer를 못 넘겼다고 그 멤버에게 알림 (수신자 취소인 file_cancel로 위장 안 함). 못 나가면 링크를 닫음
  Future<bool> sendFileUnavailable(
    String transferId, {
    required String attemptId,
    required String targetId,
  }) => sendRawInnerOrClose(
    InnerFrame.fileUnavailable(
      transferId,
      attempt: attemptId,
      target: targetId,
    ),
  );

  // 호스트 전용: 멤버의 대상 지정 offer를 정책상 거부했음을 알림 (경로 충돌, 타 기기 주소 위조, 자기 자신 대상, 경로 상한 초과 등).
  // 수신자 대신 file_cancel로 취소하며 전송 실패 시 링크를 닫음
  Future<bool> sendOfferRefusal(
    String transferId, {
    required String attemptId,
    required String targetId,
    String? targetAlias,
  }) => sendRawInnerOrClose(<String, dynamic>{
    ...InnerFrame.fileCancel(transferId, attempt: attemptId),
    'pid': targetId,
    'from': ?targetAlias,
  });

  // pushToken은 수신 측이 발급한 POST 인가 토큰임 (1:1 앱 링크는 암호화 전송되며 웹 게스트는 평문 링크로 전달됨)
  Future<void> sendFileAccept(
    String transferId, {
    required String attemptId,
    required String pushToken,
  }) => _sendInner(
    InnerFrame.fileAccept(transferId, attempt: attemptId, token: pushToken),
  );

  Future<void> sendFileReject(String transferId, {required String attemptId}) =>
      _sendInner(InnerFrame.fileReject(transferId, attempt: attemptId));

  Future<void> sendFileCancel(String transferId, {required String attemptId}) =>
      _sendInner(InnerFrame.fileCancel(transferId, attempt: attemptId));

  // 실패한 시도를 다시 받고 싶다고 요청: 보내는 쪽이 새 attempt·토큰으로 다시 offer함
  Future<void> sendFileRetry(String transferId, {required String attemptId}) =>
      _sendInner(InnerFrame.fileRetry(transferId, attempt: attemptId));

  // 바이트 검증과 커밋이 끝난 뒤 한 번 전송함. 발신 측은 EOF가 아니라 이 ACK를 수신해야 완료로 처리함. receipt는 선택적 서명 영수증임
  Future<void> sendFileReceived(
    String transferId, {
    required String attemptId,
    Map<String, dynamic>? receipt,
  }) => _sendInner(
    InnerFrame.fileReceived(transferId, attempt: attemptId, receipt: receipt),
  );

  // 1:1 앱 피어처럼 살아 있는 암호 세션이 있으면 true. 호출부가 이걸 먼저 보고 암호화 여부를 정함
  bool get canSealFileChunks => _crypto?.isReady ?? false;

  // 파일 서브키로 암호화 봉인함. canSealFileChunks가 false면 StateError를 던짐
  Future<({Uint8List nonce, Uint8List cipher, Uint8List mac})> sealFileChunk(
    Uint8List bytes, {
    required Uint8List aad,
  }) {
    final crypto = _crypto;
    if (crypto == null || !crypto.isReady) {
      throw StateError('sealFileChunk called without a ready crypto session');
    }
    return crypto.sealBytes(bytes, aad: aad);
  }

  Future<Uint8List> openFileChunk({
    required Uint8List nonce,
    required Uint8List cipher,
    required Uint8List mac,
    required Uint8List aad,
  }) {
    final crypto = _crypto;
    if (crypto == null || !crypto.isReady) {
      throw StateError('openFileChunk called without a ready crypto session');
    }
    return crypto.openBytes(nonce: nonce, cipher: cipher, mac: mac, aad: aad);
  }
}
