part of '../in_memory_store.dart';

const String kMessageCommitDomain = 'intragram/message-commitment/v1';
const String kCleanupCommitDomain = 'intragram/cleanup-commitment/v1';

final RegExp _peerIdPattern = RegExp(r'^[0-9a-f]{32}$');

// 소각 정책이 발동한 순간 지우기 직전 레코드에서 커밋먼트를 잡음 (localBurns는 지운 뒤 id만 나가서 그 뒤엔 맥락이 없음).
// 본문은 여기서 해시만 하고 비동기 서명 쪽엔 커밋먼트 값만 넘김 (본문 참조도, 커밋먼트를 여는 salt도 증적에 안 남음)
String? _attestBurn(
  _InMemoryStoreState s,
  EphemeralMessage message,
  BurnCause cause,
) {
  if (cause == BurnCause.replaced ||
      message.kind == MessageKind.system ||
      !s.evidence.canSign) {
    return null;
  }
  final transferId = message.transferId;
  final commitment = _messageCommitment(s, message);
  final peer = message.isMine
      ? s._conversations[message.conversationId]?.peerId
      : message.senderPeerId;
  unawaited(
    s.evidence.issue(
      AttestationDraft(
        kind: AttestationKind.burnTriggered,
        subjectId: message.id,
        counterpartId: peer != null && _peerIdPattern.hasMatch(peer)
            ? peer
            : null,
        commitment: commitment,
        policy: _burnPolicy(cause, message.ttlSeconds),
        outcome: 'burned',
      ),
      conversationId: message.conversationId,
      transferId: transferId,
    ),
  );
  return commitment;
}

String _messageCommitment(_InMemoryStoreState s, EphemeralMessage message) {
  final transferId = message.transferId;
  final transfer = transferId == null ? null : s._transfers[transferId];
  return saltedCommitment(kMessageCommitDomain, <Object?>[
    message.id,
    message.kind.name,
    message.text ?? '',
    transferId ?? '',
    transfer?.fileName ?? '',
    transfer?.totalBytes ?? 0,
    transfer?.contentCommitment ?? transfer?.digest ?? '',
    message.createdAt.millisecondsSinceEpoch,
    message.ttlSeconds,
  ]);
}

String _burnPolicy(BurnCause cause, int ttlSeconds) => switch (cause) {
  BurnCause.ttlAfterRead => 'burn/ttl-read:${ttlSeconds}s',
  BurnCause.unreadCeiling => 'burn/unread-ceiling:24h',
  BurnCause.deletedForEveryone => 'burn/delete-everyone',
  BurnCause.deletedForMe => 'burn/delete-me',
  BurnCause.peerRequest => 'burn/peer-request',
  BurnCause.replaced => 'burn/replaced',
};

// 앱이 맡은 자원 정리(네트워크 토큰·source·조각 파일, 음성 RAM 바이트)가 끝나면 completed, 실패하면 failed로 기록함.
// 세대는 사건 시점에 잡아서 정리가 끝나기 전 secureWipe(패닉)가 지나갔으면 그 뒤 세션에 증적을 안 남김
void _attestCleanup(
  _InMemoryStoreState s, {
  required Future<void> done,
  required String subjectId,
  required String conversationId,
  required String policy,
  List<Object?> fields = const [],
  String? captured,
  int? sinceGeneration,
  String? attemptId,
  String? counterpartId,
  String? transferId,
}) {
  final result = done.then((_) => true, onError: (Object _) => false);
  if (!s.evidence.canSign) return;
  final generation = sinceGeneration ?? s.evidence.generation;
  final commitment = captured ?? saltedCommitment(kCleanupCommitDomain, fields);
  unawaited(
    result.then(
      (ok) => s.evidence.issue(
        AttestationDraft(
          kind: ok
              ? AttestationKind.cleanupCompleted
              : AttestationKind.cleanupFailed,
          subjectId: subjectId,
          attemptId: attemptId,
          counterpartId: counterpartId,
          commitment: commitment,
          policy: policy,
          outcome: ok ? 'completed' : 'failed',
        ),
        conversationId: conversationId,
        transferId: transferId,
        sinceGeneration: generation,
      ),
    ),
  );
}
