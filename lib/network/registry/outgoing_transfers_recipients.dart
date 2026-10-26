part of 'outgoing_transfers.dart';

// 수신자 한 명이 이번 attempt에서 어디까지 왔나. failed는 재시도할 수 있고 그 뒤 셋은 끝
enum _RecipientPhase {
  offered,
  accepted,
  transferring,
  awaitingAck,
  complete,
  failed,
  rejected,
  cancelled,
}

// 수신자 한 명의 상태 (1:1도 똑같이 씀). attempt·토큰·EOF·ACK·타이머가 다 여기 있어서 다른 수신자나 옛 attempt 프레임이 못 건드림
class _OutgoingRecipient {
  _OutgoingRecipient({
    required this.key,
    required this.attemptId,
    this.pullToken,
  });

  final String key;

  // 재시도 때만 새로 발급됨
  String attemptId;

  // pull 수신자가 GET에 실을 이번 시도 전용 토큰 (쓰면 끝, 재시도가 새로 줌)
  String? pullToken;

  // push 수신자가 file_accept로 보내준 POST /api/transfer 토큰
  String? pushToken;

  _RecipientPhase phase = _RecipientPhase.offered;

  // 이 attempt의 데이터 슬롯(pull이면 GET, push면 POST)을 이미 썼는가 (중복 GET/취소 뒤 재사용 방지)
  bool tokenConsumed = false;

  // 실제 wire EOF를 봤는가 (push: POST 200 완료, pull: 응답 body EOF)
  bool wireEof = false;

  // 유효한 ACK를 받았나. EOF보다 먼저 올 수 있어서 wireEof와 둘 다 참이어야 완료
  bool ackReceived = false;

  String? error;

  // ACK 대기 타이머: 이 수신자/attempt에만 귀속되고 attempt가 바뀌면(재시도) 취소됨
  Timer? ackTimer;

  CancelToken? cancelToken;

  // 지금 도는 작업 (push 전송, GET 스트리밍). drain 때 기다림
  Future<void>? active;

  // 이 attempt의 ACK에 실려 온 수신 영수증 (완료할 때 확인함)과 내보낸 평문의 SHA-256 (offer 해시가 없는 1:1용)
  SignedAttestation? receipt;
  String? sentDigest;

  bool get isActive =>
      phase == _RecipientPhase.accepted ||
      phase == _RecipientPhase.transferring ||
      phase == _RecipientPhase.awaitingAck;

  bool get isTerminal =>
      phase == _RecipientPhase.complete ||
      phase == _RecipientPhase.rejected ||
      phase == _RecipientPhase.cancelled;

  void stopActivity() {
    ackTimer?.cancel();
    ackTimer = null;
    cancelToken?.cancel();
  }

  void fail() {
    stopActivity();
    error = 'network';
    phase = _RecipientPhase.failed;
  }

  // 재시도: 옛 attempt 흔적(토큰·EOF·ACK·타이머)을 다 버림
  void startNewAttempt(String newAttemptId, {String? newPullToken}) {
    stopActivity();
    cancelToken = null;
    attemptId = newAttemptId;
    pullToken = newPullToken;
    pushToken = null;
    phase = _RecipientPhase.offered;
    tokenConsumed = false;
    wireEof = false;
    ackReceived = false;
    error = null;
    receipt = null;
    sentDigest = null;
  }
}

extension _OutgoingTransfersRecipients on OutgoingTransfers {
  // 인증된 발신자 ID가 이 전송의 수신자 키와 정확히 일치해야 함
  _OutgoingRecipient? _recipientFor(
    OutgoingFileSource source,
    String actorKey,
  ) {
    return source._recipients[actorKey];
  }

  // 수신자에게 보낼 링크. 방 멤버로서 낸 제안은 늘 호스트 링크고, 명단에서 빠진(나간) 수신자면 null
  PeerLink? _linkForRecipient(
    OutgoingFileSource source,
    _OutgoingRecipient recipient,
  ) {
    if (!source.viaRelayHost) {
      return _linksForTransfer(
        source.conversationId,
      ).firstWhereOrNull((link) => recipientKeyOf(link) == recipient.key);
    }
    final roster =
        store.conversation(source.conversationId)?.roomRecipientIds ??
        const <String>[];
    return roster.contains(recipient.key)
        ? _relayHostLink(source.conversationId)
        : null;
  }

  // 수신자 상태로 화면용 레코드를 다시 계산함 (ACK 하나가 전체를 완료로 안 만듦): 하나라도 진행 중이면 transferring,
  // 대기면 offered, 재시도할 실패가 있으면 failed, 다 끝났으면 받은 사람이 있으면 complete, 전원 거절이면 rejected, 나머진 cancelled
  void _syncTransfer(String transferId) {
    final source = _outgoing[transferId];
    if (source == null || source._recipients.isEmpty) return;
    final all = source._recipients.values.toList();
    final TransferState state;
    if (all.any((r) => r.isActive)) {
      state = TransferState.transferring;
    } else if (all.any((r) => r.phase == _RecipientPhase.offered)) {
      state = TransferState.offered;
    } else if (all.any((r) => r.phase == _RecipientPhase.failed)) {
      state = TransferState.failed;
    } else if (all.any((r) => r.phase == _RecipientPhase.complete)) {
      state = TransferState.complete;
    } else if (all.every((r) => r.phase == _RecipientPhase.rejected)) {
      state = TransferState.rejected;
    } else {
      state = TransferState.cancelled;
    }
    final error = all
        .firstWhereOrNull((r) => r.phase == _RecipientPhase.failed)
        ?.error;
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(
        state: state,
        error: state == TransferState.failed ? (error ?? 'network') : null,
        clearError: state != TransferState.failed,
        transferredBytes: state == TransferState.complete ? source.size : null,
        bytesPerSecond: state == TransferState.transferring ? null : 0,
      ),
    );
    if (all.every((r) => r.isTerminal)) _removeSource(transferId);
  }

  // 쓸 수신자가 없는 source를 버림. 도는 작업이 있으면 끝난 뒤에 (먼저 지우면 그 정리를 기다릴 길이 없음)
  void _removeSource(String transferId) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final pending = [
      ...source._recipients.values.map((r) => r.active).nonNulls,
      ?source._hashing,
    ];
    if (pending.isEmpty) {
      _outgoing.remove(transferId);
      _retireSource(transferId, source);
      return;
    }
    unawaited(
      Future.wait(pending).then((_) {
        if (identical(_outgoing[transferId], source)) {
          _outgoing.remove(transferId);
        }
        _retireSource(transferId, source);
      }),
    );
  }

  // reader가 다 끝난 뒤에만 부름. 실패는 남겨서 clear가 던짐
  Future<Object?> _releaseSource(OutgoingFileSource source) async {
    try {
      await source._release();
    } on Object catch (e) {
      _releaseFailures.add(e);
      return e;
    }
    return null;
  }

  // _releaseSource를 기다리지 않고 시작하되 추적함 (clear/dispose가 끝까지 기다릴 수 있게)
  Future<Object?> _retireSource(String id, OutgoingFileSource source) {
    final previous = _retiring[id];
    if (previous != null) return previous;
    final release = _retiring[id] = _releaseSource(source);
    final pending = release.then<void>((failure) {
      if (failure == null) _retiring.remove(id);
    });
    _pendingReleases.add(pending);
    unawaited(pending.whenComplete(() => _pendingReleases.remove(pending)));
    return release;
  }

  Future<void> _drainRecipients(OutgoingFileSource source) async {
    for (final r in source._recipients.values.toList()) {
      final active = r.active;
      if (active != null) await active;
    }
    await source._hashing; // 첫 offer 전 해시 읽기
  }
}
