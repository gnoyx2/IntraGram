part of 'outgoing_transfers.dart';

// 수신자 한 명이 이번 attempt에서 어디까지 왔는지. failed는 재시도 가능한
// 상태(새 attempt/토큰으로 되돌릴 수 있음), 나머지 세 종결 상태는 아님
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

// 수신자 한 명의 전송 상태 (OutgoingFileSource._recipients의 값,
// 1:1도 수신자 한 명짜리로 똑같이 씀). attempt/토큰/EOF/ACK/ACK 타이머가
// 전부 이 객체에 귀속돼서 다른 수신자(또는 이전 attempt)의 프레임이 이 상태를 못 건드림
class _OutgoingRecipient {
  _OutgoingRecipient({
    required this.key,
    required this.attemptId,
    this.pullToken,
  });

  // recipientKeyOf: RAM 전용 라우팅 키
  final String key;

  // 재시도 때만 새로 발급됨
  String attemptId;

  // pull 수신자가 GET /api/download/<id>에 실을 이 시도
  // 전용 토큰 (tokenConsumed가 되면 죽음, 재시도가 새 값으로 바꿈)
  String? pullToken;

  // push 수신자가 file_accept로 보내준 POST /api/transfer 토큰
  String? pushToken;

  _RecipientPhase phase = _RecipientPhase.offered;

  // 이 attempt의 데이터 슬롯(pull이면 GET, push면 POST)을 이미 썼는가 (중복 GET/취소 뒤 재사용 방지)
  bool tokenConsumed = false;

  // 실제 wire EOF를 봤는가 (push: POST 200 완료, pull: 응답 body EOF)
  bool wireEof = false;

  // 유효한 file_received ACK를 받았는가. EOF보다 먼저 올 수
  // 있어서 곧바로 성공으로 안 치고 wireEof와 둘 다 참일 때만 complete
  bool ackReceived = false;

  String? error;

  // ACK 대기 타이머: 이 수신자/attempt에만 귀속되고 attempt가 바뀌면(재시도) 취소됨
  Timer? ackTimer;

  // 지금 도는 push 전송/GET 스트리밍을 끊는 토큰
  CancelToken? cancelToken;

  // 지금 도는 작업 (push 전송, GET 스트리밍). drain 때 기다림
  Future<void>? active;

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

  // 새 attempt로 되돌림(재시도): 이전 attempt의 모든 흔적(토큰/EOF/ACK/타이머/소유자)을 버림
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

  // recipient에게 프레임을 보낼 링크. 방 멤버로서 낸 제안은 수신자가 누구든 인증된 호스트 링크 하나로만 나가고,
  // 호스트 명단에 없는(이미 방을 나간) 수신자에게는 null
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

  // 수신자 상태들로 공유 FileTransfer 레코드(화면 표시용)를
  // 다시 계산함 (첫 ACK 하나가 전체를 complete로 만들지 않음):
  // 진행 중이 하나라도 있으면 transferring, 대기 중이면 offered, 재시도 가능한 실패가 있으면 failed,
  // 전부 끝났으면 한 명이라도 받았으면 complete / 전원 거절이면 rejected / 그 외 cancelled
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

  // 더 이상 쓸 수신자가 없는 source를 버림. 아직 도는 작업(취소 직후의 push/GET)이 있으면 그게 끝난 뒤에 버림:
  // source를 먼저 지우면 그 작업의 정리를 기다릴 방법(drain)이 사라짐
  void _removeSource(String transferId) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final pending = [
      ...source._recipients.values.map((r) => r.active).nonNulls,
      ?source._hashing,
    ];
    if (pending.isEmpty) {
      _outgoing.remove(transferId);
      _retireSource(source);
      return;
    }
    unawaited(
      Future.wait(pending).then((_) {
        if (identical(_outgoing[transferId], source)) {
          _outgoing.remove(transferId);
        }
        _retireSource(source);
      }),
    );
  }

  // source의 native 자원을 놓음: reader가 이미 다 끝난 뒤에만 부름.
  // 실패는 _releaseFailures에 남겨서 clear가 던짐 (삼키지 않음).
  // 멱등
  Future<void> _releaseSource(OutgoingFileSource source) async {
    try {
      await source._release();
    } on Object catch (e) {
      _releaseFailures.add(e);
    }
  }

  // _releaseSource를 기다리지 않고 시작하되 추적함 (clear/dispose가 끝까지 기다릴 수 있게)
  void _retireSource(OutgoingFileSource source) {
    final release = _releaseSource(source);
    _pendingReleases.add(release);
    unawaited(release.whenComplete(() => _pendingReleases.remove(release)));
  }

  // source의 모든 수신자가 하던 일이 끝나길 기다림 (취소/정리 뒤)
  Future<void> _drainRecipients(OutgoingFileSource source) async {
    for (final r in source._recipients.values.toList()) {
      final active = r.active;
      if (active != null) await active;
    }
    await source._hashing; // 첫 offer 전 해시 읽기
  }
}
