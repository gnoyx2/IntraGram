import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/free_space.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/path_safety.dart';
import 'package:intragram/core/secure_bytes.dart'
    show SecureBytes, constantTimeEquals, generateSecureToken;
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/incoming_path_resolver.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

export 'package:intragram/network/registry/incoming_path_resolver.dart';

part 'incoming_transfers_accept.dart';
part 'incoming_transfers_cleanup.dart';
part 'incoming_transfers_pull.dart';
part 'incoming_transfers_lifecycle.dart';
part 'incoming_transfers_receive.dart';

// 파일 전송의 받는 절반: 인커밍 제안 수락/거절, 안전한 목적지 고르기, 서버가 넘겨주는 바이트 스트림 받기
// 목적지 폴더 선택/캐싱은 _pathResolver에 위임하고, 유저가 고른 폴더는 이번 실행만(RAM 전용) 기억함
// (영속하면 유저 의도를 디스크에 쓰는 거라 제로 디스크 규칙 위반: 다음 실행에 다시 물어봄)
class IncomingTransfers {
  IncomingTransfers({
    required this.store,
    required PeerLink? Function(String conversationId) linkFor,
    PeerLink? Function(FileTransfer transfer)? linkForTransfer,
    required this.gate,
    this.chooseDirectory,
  })
    // 호출부에서 이름 있는 linkFor:가 this._linkFor보다 잘 읽힘
    // ignore: prefer_initializing_formals
    : _linkFor = linkFor,
       _linkForTransfer = linkForTransfer ?? ((t) => linkFor(t.conversationId));

  final InMemoryStore store;
  final PeerLink? Function(String conversationId) _linkFor;
  final PeerLink? Function(FileTransfer transfer) _linkForTransfer;

  // 동시 활성 전송 상한: TransferCoordinator가 OutgoingTransfers와 공유하는 인스턴스를 줌
  final TransferConcurrencyGate gate;

  // 수락된 파일이 어디 써질지 고르는 seam (프로덕션은 null이라 내부 기본 플랫폼 로직이 돌고, 테스트는 임시 디렉토리 주입)
  final Future<String?> Function(String suggestedName)? chooseDirectory;

  late final IncomingPathResolver _pathResolver = IncomingPathResolver(
    chooseDirectory: chooseDirectory,
  );

  final Map<String, _IncomingFile> _incoming = <String, _IncomingFile>{};

  // clear가 admission을 닫은 뒤 true: 이후 accept/pull/receive는 새
  // 작업을 시작 안 함. registry는 disposeAll 뒤 새 인스턴스로 교체되므로 되살아나지
  // 않음
  bool _closed = false;

  // 이번 세션이 소유한 partial 전부 ((전송 id, attempt)별, 수락 때 예약한
  // 것 + 직접 pull이 예약한 것). _incoming은 receive가 검증 뒤 지워서
  // 활성 수신을 못 담으므로 여기서 끝까지 추적 (자세한 건 incoming_transfers_cleanup.dart)
  final Map<String, _OwnedPartial> _activePartials = <String, _OwnedPartial>{};

  // 배경 정리 경로(UI 취소 등)에서 partial 삭제가 실패한 기록
  // (전송 id별): clear가 마지막에 그대로 보고함 (삼키지 않음)
  // 나중에 같은 전송의 삭제가 성공하면 기록은 지워짐
  final Map<String, List<Object>> _cleanupFailures = <String, List<Object>>{};

  // 전송 중인 인커밍 전송을 무를 수 있는 토큰 (push의 receive, pull의
  // _pullDirect/_pullVoice 공용). 시작할 때 세팅하고 끝나면 지움
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  // transferId별 지금 실제로 도는 I/O 작업 (정리 전에 await)
  final Map<String, Future<void>> _active = <String, Future<void>>{};

  // 폴더 선택 중 같은 제안을 다시 눌러도 예약/수신 슬롯은 한 번만 만듦
  final Map<String, Future<void>> _accepting = <String, Future<void>>{};

  void _track(String transferId, Future<void> future) =>
      _trackIncoming(this, transferId, future);

  // 받을 공간이 모자람. 이번 세션에 고른 폴더를 잊어서 데스크톱 재시도가 다른 폴더를 묻게 함 (모바일은 고정 폴더)
  void _failForSpace(String transferId) {
    _pathResolver.clear();
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.failed, error: 'diskFull'),
    );
  }

  // 받는 중 실패를 사유로 기록. 공간 부족이면 위와 같이 폴더를 잊음
  void _failReceive(String transferId, Object error) {
    final reason = classifyTransferError(error);
    if (reason == 'diskFull') return _failForSpace(transferId);
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.failed, error: reason),
    );
  }

  Future<void> accept(String transferId) {
    if (_closed) return Future<void>.value();
    final existing = _accepting[transferId];
    if (existing != null) return existing;
    final pending = _acceptIncoming(this, transferId);
    _accepting[transferId] = pending;
    unawaited(
      pending.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_accepting[transferId], pending)) {
          _accepting.remove(transferId);
        }
      }),
    );
    return pending;
  }

  Future<void> reject(String transferId) => _rejectIncoming(this, transferId);

  Future<bool> receive({
    required String transferId,
    required String attemptId,
    required String token,
    required Stream<List<int>> body,
    required int headerDeclaredSize,
  }) {
    final future = _receiveIncoming(
      this,
      transferId: transferId,
      attemptId: attemptId,
      token: token,
      body: body,
      headerDeclaredSize: headerDeclaredSize,
    );
    _track(transferId, future);
    return future;
  }

  Future<void> acceptBatch(String conversationId, String batchId) =>
      _acceptBatch(this, conversationId, batchId);

  Future<void> rejectBatch(String conversationId, String batchId) =>
      _rejectBatch(this, conversationId, batchId);

  void cancelTransfer(String transferId) => _cancelTransfer(this, transferId);

  void handleCancelledByPeer(
    String transferId, {
    required String attemptId,
    required String senderPeerId,
  }) => _handleCancelledByPeer(this, transferId, attemptId, senderPeerId);

  Future<void> retryTransfer(String transferId) =>
      _retryTransfer(this, transferId);

  Future<void> discard(String transferId) => _discard(this, transferId);

  Future<void> handleLinkClosed(
    String conversationId, {
    String? senderPeerId,
  }) => _handleLinkClosedIncoming(this, conversationId, senderPeerId);

  Future<void> clear() => _clearIncoming(this);

  // push accept로 발급한 POST /api/transfer 토큰 (테스트가 살아
  // 있는 PeerLink 없이 accept -> receive를 직접 호출할 때만 씀)
  @visibleForTesting
  String? debugPushTokenFor(String transferId) => _incoming[transferId]?.token;

  // transfer가 암호화됐다고 주장하면 이 대화의 링크에서 복호화 함수를 가져옴 (그룹 방/웹 게스트면 null)
  // 크립토 세션이 없는데 암호화됐다고 하면 조용히 평문으로 넘기는 대신 던짐: 쓰레기를 파일 바이트인 척 안 흘림
  OpenChunk? _decryptorFor(FileTransfer transfer) {
    if (!transfer.encrypted) return null;
    final link = _linkFor(transfer.conversationId);
    if (link == null || !link.canSealFileChunks) {
      throw SecurityException(
        'transfer ${transfer.id} claims to be encrypted but no crypto '
        'session is available for this conversation',
      );
    }
    return link.openFileChunk;
  }
}
