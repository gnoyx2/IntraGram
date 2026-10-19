part of '../models.dart';

@immutable
class FileTransfer {
  const FileTransfer({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.fileName,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.mimeType,
    this.localPath,
    this.state = TransferState.offered,
    this.bytesPerSecond = 0,
    this.error,
    this.batchLabel,
    this.batchId,
    this.srcHost,
    this.srcPort,
    this.thumbBytes,
    this.preview,
    this.voice = false,
    this.voiceBytes,
    this.encrypted = false,
    this.attemptId,
    this.pullToken,
    this.mode,
    this.senderPeerId,
    this.digest,
  });

  final String id;
  final String conversationId;
  final TransferDirection direction;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final String? mimeType;

  // 인커밍 그룹 방 제안이면 원본 멤버의 사설 IPv4 + 서버 포트. 받는 쪽이 GET /api/download/<id>를 그 멤버에게
  // 직접 침. RAM 전용 (라우팅 정보라 직렬화 안 함)
  final String? srcHost;
  final int? srcPort;

  // 이미지 제안의 수락 전 미리보기용 다운스케일 PNG. RAM 전용
  final Uint8List? thumbBytes;

  // 스필된 긴 텍스트 제안의 수락 전 미리보기 스니펫. thumbBytes와 배타적. RAM 전용
  final String? preview;

  // 음성 메시지면 true: 자동 수락 + RAM 재생, 디스크/보관소에 안 감
  final bool voice;

  // 수신한 음성의 오디오 바이트. 수락하면서 RAM으로 당겨옴. 디스크에 안 쓰고 직렬화 안 함,
  // 소각/와이프하면 같이 사라짐. 보낸 쪽은 항상 null
  final Uint8List? voiceBytes;

  // 이 전송 바이트가 링크의 파일 전송 서브키로 봉인됐는지 (1:1만, 그룹 방
  // 직접 pull/웹 게스트는 항상 false) UI 자물쇠 아이콘용. RAM 전용
  final bool encrypted;

  // 전송 시도의 불투명 id. transferId와 별개로 offer마다 새로 발급되고
  // AEAD AAD와 GET/POST 인가 토큰이 이 값에 묶임. RAM 전용
  final String? attemptId;

  // 그룹 방 직접 pull(또는 음성)에서 받는 쪽이 GET /api/download/<id>에 실어
  // 보낼 32바이트 보안 난수(base64url): offer를 낸 쪽이 발급. 1:1 push 제안이면
  // null (accept 쪽이 별도 토큰을 만듦). RAM 전용, 로그/볼트/UI에 절대 안 보임
  final String? pullToken;

  // 받는 쪽이 바이트를 가져오는 방식 (FileOfferInner.mode를 타입으로 고정한 값). RAM 전용
  // null이면(legacy vault 이력) 구버전 프레임처럼 push로 취급
  final FileTransferMode? mode;

  // 인커밍: offer를 보낸 상대의 인증된 peerId (1:1이면 링크 상대, 방이면 호스트가 도장 찍은 원 발신자)
  // 같은 id의 재offer/취소/재시도가 그 발신자에게서만 오게 묶음 (다른
  // 멤버가 남의 전송 id를 가로채지 못하게) 아웃고잉은 null, RAM 전용
  final String? senderPeerId;

  // 인커밍 방 전송: offer가 실어 온 내용 SHA-256 base64. 받은 바이트가 다르면 지우고 실패. RAM 전용
  final String? digest;

  // 아웃고잉: 원본 파일 경로. 인커밍: 선택한 목적지 경로 (수락 시 세팅)
  final String? localPath;

  final TransferState state;
  final double bytesPerSecond;
  final String? error;

  // 다중 파일 배치의 일부면 "2 / 5", 아니면 null. 제안 만들 때 한 번 세팅되고 안 바뀜
  final String? batchLabel;

  // 같은 배치의 파일들이 공유하는 불투명 id ("전부 수락/거절" 버튼이 형제 전송을 찾는 용도). batchLabel처럼 안 바뀜
  final String? batchId;

  double get progress => totalBytes <= 0
      ? 0
      : (transferredBytes / totalBytes).clamp(0, 1).toDouble();

  bool get isActive =>
      state == TransferState.accepted || state == TransferState.transferring;

  bool get isDone => state == TransferState.complete;

  FileTransfer copyWith({
    int? transferredBytes,
    String? localPath,
    TransferState? state,
    double? bytesPerSecond,
    String? error,
    bool clearError = false,
    Uint8List? voiceBytes,
    String? attemptId,
    String? pullToken,
    FileTransferMode? mode,
    String? srcHost,
    int? srcPort,
  }) {
    return FileTransfer(
      id: id,
      conversationId: conversationId,
      direction: direction,
      fileName: fileName,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      mimeType: mimeType,
      localPath: localPath ?? this.localPath,
      state: state ?? this.state,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      error: clearError ? null : (error ?? this.error),
      batchLabel: batchLabel,
      batchId: batchId,
      srcHost: srcHost ?? this.srcHost,
      srcPort: srcPort ?? this.srcPort,
      thumbBytes: thumbBytes,
      preview: preview,
      voice: voice,
      voiceBytes: voiceBytes ?? this.voiceBytes,
      encrypted: encrypted,
      attemptId: attemptId ?? this.attemptId,
      pullToken: pullToken ?? this.pullToken,
      mode: mode ?? this.mode,
      senderPeerId: senderPeerId,
      digest: digest,
    );
  }

  // 속도/에러는 임시라 안 담음. 스토어는 완료된 전송만 보관함 (InMemoryStore.toSnapshot 참고)
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'conversationId': conversationId,
    'direction': direction.name,
    'fileName': fileName,
    'totalBytes': totalBytes,
    'transferredBytes': transferredBytes,
    if (mimeType != null) 'mimeType': mimeType,
    if (localPath != null) 'localPath': localPath,
    'state': state.name,
    if (batchLabel != null) 'batchLabel': batchLabel,
    if (batchId != null) 'batchId': batchId,
  };

  factory FileTransfer.fromJson(Map<String, dynamic> j) => FileTransfer(
    id: (j['id'] ?? '').toString(),
    conversationId: (j['conversationId'] ?? '').toString(),
    direction: _enumByName(
      TransferDirection.values,
      j['direction'],
      TransferDirection.incoming,
    ),
    fileName: (j['fileName'] ?? 'file').toString(),
    totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
    transferredBytes: (j['transferredBytes'] as num?)?.toInt() ?? 0,
    mimeType: j['mimeType']?.toString(),
    localPath: j['localPath']?.toString(),
    state: _enumByName(
      TransferState.values,
      j['state'],
      TransferState.complete,
    ),
    batchLabel: j['batchLabel']?.toString(),
    batchId: j['batchId']?.toString(),
  );

  // attempt/토큰/원본 주소도 비교함: 같은 상태(offered)에서 보내는 쪽이 새 attempt/토큰으로 다시 offer한 갱신을
  // updateTransfer가 "변화 없음"으로 버리면 받는 쪽이 낡은 토큰으로 GET함
  // 이 값들은 재offer 때만 바뀌어 진행률 갱신 빈도엔 영향 없음
  @override
  bool operator ==(Object other) =>
      other is FileTransfer &&
      other.id == id &&
      other.transferredBytes == transferredBytes &&
      other.state == state &&
      other.localPath == localPath &&
      other.attemptId == attemptId &&
      other.pullToken == pullToken &&
      other.srcHost == srcHost &&
      other.srcPort == srcPort;

  @override
  int get hashCode => Object.hash(
    id,
    transferredBytes,
    state,
    localPath,
    attemptId,
    pullToken,
    srcHost,
    srcPort,
  );
}
