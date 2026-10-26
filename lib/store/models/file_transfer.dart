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
    this.contentCommitment,
    this.senderPubKey,
  });

  final String id;
  final String conversationId;
  final TransferDirection direction;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final String? mimeType;

  // 방에서 들어온 제안이면 원래 보낸 멤버의 사설 IPv4와 서버 포트. 받는 쪽이 GET /api/download/<id>를 그 멤버에게 바로 침.
  // RAM 전용 (라우팅 정보라 직렬화 안 함)
  final String? srcHost;
  final int? srcPort;

  // 이미지 제안의 수락 전 미리보기용 다운스케일 PNG. RAM 전용
  final Uint8List? thumbBytes;

  // 길어서 파일로 넘긴 텍스트 제안의 수락 전 미리보기. thumbBytes와 같이 안 옴. RAM 전용
  final String? preview;

  // 음성 메시지면 true: 자동 수락하고 RAM에서 재생, 디스크·보관소엔 안 감
  final bool voice;

  // 받은 음성의 오디오 바이트. 수락하면서 RAM으로 당겨 옴. 디스크에 안 쓰고 직렬화도 안 하고 소각·와이프 때 같이 덮음.
  // 보낸 쪽은 늘 null
  final Uint8List? voiceBytes;

  // 이 전송 바이트를 링크의 파일 서브키로 봉인하는지 (1:1만. 방 직접 pull·웹 게스트는 늘 false). 복호화 여부와 UI 자물쇠가 이걸 봄. RAM 전용
  final bool encrypted;

  // 전송 시도의 불투명 id. transferId와 별개로 offer마다 새로 나오고 AEAD AAD와 GET·POST 인가 토큰이 이 값에 묶임. RAM 전용
  final String? attemptId;

  // 방 직접 pull(이나 음성)에서 받는 쪽이 GET /api/download/<id>에 실어 보낼 32바이트 난수(base64url). offer를 낸 쪽이 발급함.
  // 1:1 push 제안이면 null (수락하는 쪽이 따로 토큰을 만듦). RAM 전용이고 로그·보관소·UI엔 절대 안 나옴
  final String? pullToken;

  // 받는 쪽이 바이트를 가져오는 방식 (FileOfferInner.mode를 타입으로 고정). RAM 전용. null이면(옛 vault 기록) 옛 프레임처럼 push로 봄
  final FileTransferMode? mode;

  // 들어온 전송: offer를 보낸 쪽의 인증된 peerId (1:1이면 링크 상대, 방이면 호스트가 도장 찍은 원래 보낸 사람).
  // 같은 id의 재offer·취소·재시도가 그 사람한테서만 오게 묶음 (다른 멤버가 남의 전송 id를 가로채지 못하게). 보내는 쪽은 null, RAM 전용
  final String? senderPeerId;

  // offer에 실려 온 내용 SHA-256(base64). 있으면 받은 바이트가 다를 때 지우고 실패. RAM 전용
  final String? digest;

  // 직접 잰 내용 해시와 발신자 공개키(base64). 증적 전용 RAM 값이며 offer dg·Vault와 별개.
  final String? contentCommitment;
  final String? senderPubKey;

  // 보내는 쪽: 원본 파일 경로. 받는 쪽: 고른 저장 경로 (수락 때 채움)
  final String? localPath;

  final TransferState state;
  final double bytesPerSecond;
  final String? error;

  // 여러 파일 묶음의 일부면 '2 / 5', 아니면 null. 제안을 만들 때 한 번 정하고 안 바뀜
  final String? batchLabel;

  // 같은 묶음의 파일들이 나눠 갖는 불투명 id ('전부 수락·거절' 버튼이 형제 전송을 찾을 때 씀). batchLabel처럼 안 바뀜
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
    String? digest,
    String? contentCommitment,
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
      digest: digest ?? this.digest,
      contentCommitment: contentCommitment ?? this.contentCommitment,
      senderPubKey: senderPubKey,
    );
  }

  // 속도·에러는 잠깐 값이라 안 담음. 스토어는 끝난 전송만 보관함 (InMemoryStore.toSnapshot 참고)
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

  // attempt·토큰·원본 주소도 비교함: 보내는 쪽이 같은 offered 상태에서 새 attempt·토큰으로 다시 offer한 걸
  // updateTransfer가 변화 없음으로 버리면 받는 쪽이 낡은 토큰으로 GET함. 이 값들은 재offer 때만 바뀌어서 진행률 갱신 빈도엔 영향 없음
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
      other.srcPort == srcPort &&
      other.digest == digest &&
      other.contentCommitment == contentCommitment;

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
    digest,
    contentCommitment,
  );
}
