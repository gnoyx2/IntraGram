part of 'incoming_transfers.dart';

// 앱이 만든 .part 하나. 어느 전송·대화 것인지 들고 있어서 정리가 딱 그 파일만 치움
class _OwnedPartial {
  const _OwnedPartial(this.transferId, this.conversationId, this.file);
  final String transferId;
  final String conversationId;
  final File file;
}

// .part 추적·정리. 예약 직후(await 전에) _activePartials에 넣고 커밋하거나 지운 뒤에만 뺌 (_incoming만 보면 받는 중이거나 pull이 만든 .part를 놓침)
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

  // 최종 이름으로 커밋돼서 더는 앱 임시 파일이 아님
  void _releasePartial(String transferId, String attemptId) =>
      _activePartials.remove(_partialKey(transferId, attemptId));

  // 이 시도를 계속해도 되나: 정리됐거나 전송이 사라졌거나 attempt가 바뀌면 false. await마다 뒤에서 불러서 늦은 결과가 끝난 세션에 .part를 못 만들게 함
  bool _isCurrent(String transferId, String attemptId) {
    if (_closed) return false;
    final transfer = store.transfer(transferId);
    return transfer != null &&
        (transfer.attemptId ?? transferId) == attemptId &&
        (transfer.state == TransferState.offered ||
            transfer.state == TransferState.accepted ||
            transfer.state == TransferState.transferring);
  }

  // 그 전송의 .part를 끝까지 다 지움 (하나가 실패해도 계속). 못 지운 건 남겨서 다음 정리가 다시 하고 TransferCleanupException
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
    _cleanupFailures.remove(transferId); // 다 치웠으니 옛 실패 기록도 지움
  }

  // 던질 곳이 없는 배경 경로판: 실패는 기록해 두고 clear가 마지막에 던짐
  Future<void> _deleteOwnedPartialsRecorded(String transferId) async {
    try {
      await _deleteOwnedPartials(transferId);
    } on TransferCleanupException catch (e) {
      _cleanupFailures[transferId] = e.failures;
    }
  }

  // 슬롯·작업·토큰·.part 중 하나라도 남은 전송 id 전부
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
