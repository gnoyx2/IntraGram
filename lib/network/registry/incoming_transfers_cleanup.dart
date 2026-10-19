part of 'incoming_transfers.dart';

// 앱이 예약해 소유한 .part 하나: 어느 전송(과 대화)의 것인지 같이 들고
// 있어서 링크 종료/discard/clear가 정확히 그 전송의 파일만 치움
class _OwnedPartial {
  const _OwnedPartial(this.transferId, this.conversationId, this.file);
  final String transferId;
  final String conversationId;
  final File file;
}

// 소유 partial의 추적/admission/정리. _incoming은 receive가 검증 뒤 자기
// 항목을 지워서 활성 수신을 못 담고(그래서 clear()가 진행 중 수신의 .part를 놓칠 수 있고),
// 직접 pull이 예약한 파셜은 어디에도 등록 안 되므로, 예약 직후(다음 await
// 전에) _activePartials에 넣고 성공적으로 커밋하거나 삭제한 뒤에만 뺌
extension _IncomingCleanup on IncomingTransfers {
  String _partialKey(String transferId, String attemptId) =>
      '$transferId|$attemptId';

  void _ownPartial(
    String transferId,
    String conversationId,
    String attemptId,
    File file,
  ) {
    _activePartials[_partialKey(transferId, attemptId)] = _OwnedPartial(
      transferId,
      conversationId,
      file,
    );
  }

  // 파셜이 최종 이름으로 커밋돼서 더는 "앱 소유 임시 파일"이 아님
  void _releasePartial(String transferId, String attemptId) =>
      _activePartials.remove(_partialKey(transferId, attemptId));

  // 이 시도를 계속해도 되는가: clear가 admission을 닫았거나(_closed), 전송이 사라졌거나(소각/삭제/discard)
  // 새 attempt로 바뀌었으면 false. 모든 await 뒤에 불러서 늦게 돌아온 폴더 선택/예약
  // 결과가 정리가 끝난 세션에 새 .part나 슬롯을 만들지 못하게 함
  bool _isCurrent(String transferId, String attemptId) {
    if (_closed) return false;
    final transfer = store.transfer(transferId);
    return transfer != null &&
        (transfer.attemptId ?? transferId) == attemptId &&
        (transfer.state == TransferState.offered ||
            transfer.state == TransferState.accepted ||
            transfer.state == TransferState.transferring);
  }

  // transferId가 소유한 모든 partial을 끝까지(하나가 실패해도 나머지도) 지우고 지운 것만 registry에서 뺌
  // 실패한 건 남겨서 다음 discard/clear가 다시 시도하고, 실패가
  // 하나라도 있으면 TransferCleanupException을 던짐
  Future<void> _deleteOwnedPartials(String transferId) async {
    final failures = <Object>[];
    final owned = _activePartials.entries
        .where((entry) => entry.value.transferId == transferId)
        .toList();
    for (final entry in owned) {
      try {
        if (entry.value.file.existsSync()) await entry.value.file.delete();
        _activePartials.remove(entry.key);
      } on FileSystemException catch (e) {
        failures.add(e);
      }
    }
    if (failures.isNotEmpty) throw TransferCleanupException(failures: failures);
    _cleanupFailures.remove(transferId); // 다 치웠으니 옛 실패 기록도 해소됨
  }

  // _deleteOwnedPartials의 비동기 배경 경로판: 던질 곳이 없으니(UI 취소 등)
  // 실패를 _cleanupFailures에 기록하고 clear가 마지막에 그대로 보고함 (삼키지 않음)
  // 실패한 partial은 registry에 남아 clear가 다시 시도함
  Future<void> _deleteOwnedPartialsRecorded(String transferId) async {
    try {
      await _deleteOwnedPartials(transferId);
    } on TransferCleanupException catch (e) {
      _cleanupFailures[transferId] = e.failures;
    }
  }

  // 정리 대상이 될 수 있는 전송 id 전부: 슬롯, 진행 중 작업, 취소 토큰, 소유 partial 중 어느 하나에라도 남아 있으면 포함
  Set<String> _ownedTransferIds() => <String>{
    ..._incoming.keys,
    ..._active.keys,
    ..._cancelTokens.keys,
    ..._activePartials.values.map((owned) => owned.transferId),
  };

  String? _conversationOf(String transferId) =>
      store.transfer(transferId)?.conversationId ??
      _incoming[transferId]?.conversationId ??
      _activePartials.values
          .where((owned) => owned.transferId == transferId)
          .map((owned) => owned.conversationId)
          .firstOrNull;
}
