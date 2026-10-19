part of 'peer_link.dart';

// PeerLinkOutbound 중 파일 전송 프레임(file_*) 보내기와 청크 seal/open
extension PeerLinkOutboundFile on PeerLink {
  // to가 있으면 방 안 특정 멤버 몫 offer (호스트가 그 멤버에게만
  // 중계). 이 링크로 프레임을 못 내보내면(닫힘/큐 상한) false
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
    ),
  );

  // 호스트 전용: 이 링크의 방 멤버가 targetId에게 낸 (전송, attempt)
  // offer를 못 넘겼다고(대상이 방에 없음/전달 실패) 그 멤버에게 알림
  // 받은 발신자는 그 수신자 몫만 재시도 가능한 실패로 돌림 (수신자의 취소를 뜻하는 file_cancel로 위장하지 않음)
  // 통지가 못 나가면 이 링크를 닫아 발신자가 영영 기다리지 않게 함
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

  // 호스트 전용: 방 멤버가 낸 대상 지정 offer를 정책상 거부했다고(남의
  // 경로/전송 id와 충돌, 다른 기기 주소, 자기 자신 대상, 경로 상한)
  // 그 멤버에게 알림. 수신자 대신 file_cancel을 보내 그 수신자 몫을 끝냄. 네트워크 실패는 sendFileUnavailable
  // 못 나가면 링크를 닫음. targetAlias는 표시용
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

  // pushToken은 방금 발급한 POST /api/transfer 인가 토큰: AEAD로 잠긴 이 링크로만 전달됨
  // (핸드셰이크 전이면 다른 inner frame처럼 큐잉되고 평문으로는 절대 안 나감)
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

  // 실패한 시도(attemptId)를 다시 받고 싶다고 보내는 쪽에 요청: 옛
  // 토큰을 재사용하지 않고 보내는 쪽이 새 attempt/토큰으로 다시 offer함
  Future<void> sendFileRetry(String transferId, {required String attemptId}) =>
      _sendInner(InnerFrame.fileRetry(transferId, attempt: attemptId));

  // 완전히 받아서(길이/AEAD 검증까지) 커밋/RAM 이전까지 마친 뒤 한 번
  // 보냄. 보내는 쪽은 GET/POST EOF가 아니라 이 ACK로만 완료 처리함
  Future<void> sendFileReceived(
    String transferId, {
    required String attemptId,
  }) => _sendInner(InnerFrame.fileReceived(transferId, attempt: attemptId));

  // 이 링크에 살아있는 크립토 세션이 있으면(1:1 앱 피어) true. 웹 게스트나 세션이 아직 안 끝났으면 false
  // 호출부(OutgoingTransfers._offer)가 이걸 먼저 확인해 암호화
  // 여부를 정하고 그다음에만 sealFileChunk/openFileChunk를
  // 씀
  bool get canSealFileChunks => _crypto?.isReady ?? false;

  // 이 링크의 파일 전송 서브키로 봉인. canSealFileChunks가 false일 때 부르면 던짐 (호출부가 먼저 확인)
  // aad는 호출부(file_transfer_crypto.dart)가 만든 청크별 associated data
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
