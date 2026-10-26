import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'package:intragram/audit/content_commitment.dart' show sha256B64;
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/app_identity.dart' show peerIdOfKey;
import 'package:intragram/core/free_space.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/path_safety.dart';
import 'package:intragram/core/secure_bytes.dart'
    show SecureBytes, constantTimeEquals, generateSecureToken;
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/peer_auth.dart' show isSmallOrderKey;
import 'package:intragram/network/protocol.dart' show wireBytes;
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
part 'incoming_transfers_receipt.dart';

// 받는 절반: 제안 수락·거절, 목적지 고르기, 서버가 넘겨준 바이트 받기. 고른 폴더는 이번 실행 동안만 다시 씀 (다음 실행엔 다시 물어봄)
class IncomingTransfers {
  IncomingTransfers({
    required this.store,
    required PeerLink? Function(String conversationId) linkFor,
    PeerLink? Function(FileTransfer transfer)? linkForTransfer,
    required this.gate,
    this.chooseDirectory,
  })
    // 호출부에선 linkFor:가 더 잘 읽힘
    // ignore: prefer_initializing_formals
    : _linkFor = linkFor,
       _linkForTransfer = linkForTransfer ?? ((t) => linkFor(t.conversationId));

  final InMemoryStore store;
  final PeerLink? Function(String conversationId) _linkFor;
  final PeerLink? Function(FileTransfer transfer) _linkForTransfer;

  // 보내는 쪽과 나눠 쓰는 동시 전송 게이트
  final TransferConcurrencyGate gate;

  // 저장 폴더를 고르는 seam (프로덕션은 null이라 플랫폼 로직, 테스트는 임시 폴더)
  final Future<String?> Function(String suggestedName)? chooseDirectory;

  late final IncomingPathResolver _pathResolver = IncomingPathResolver(
    chooseDirectory: chooseDirectory,
  );

  final Map<String, _IncomingFile> _incoming = <String, _IncomingFile>{};

  // clear가 세움: 그 뒤 accept·pull·receive는 새 작업을 안 시작함
  bool _closed = false;

  // 이번 세션이 만든 .part 전부 ((전송 id, attempt)별). _incoming은 receive가 시작하면서 지워서 여기서 끝까지 따로 추적함
  final Map<String, _OwnedPartial> _activePartials = <String, _OwnedPartial>{};

  // 배경 정리(UI 취소 등)에서 .part 삭제가 실패한 기록. clear가 마지막에 그대로 던짐 (나중에 지워지면 기록도 빠짐)
  final Map<String, List<Object>> _cleanupFailures = <String, List<Object>>{};

  // 받는 중인 전송을 끊는 토큰 (push·pull·음성 공용)
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  // transferId별 지금 실제로 도는 I/O 작업 (정리 전에 await)
  final Map<String, Future<void>> _active = <String, Future<void>>{};

  // 폴더 선택 중 같은 제안을 다시 눌러도 예약/수신 슬롯은 한 번만 만듦
  final Map<String, Future<void>> _accepting = <String, Future<void>>{};

  void _track(String transferId, Future<void> future) =>
      _trackIncoming(this, transferId, future);

  // 공간 부족: 고른 폴더를 잊어서 데스크톱 재시도가 다른 폴더를 묻게 함 (모바일은 고정 폴더)
  void _failForSpace(String transferId) {
    _pathResolver.clear();
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.failed, error: 'diskFull'),
    );
  }

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

  // push accept로 발급한 POST 토큰 (테스트가 링크 없이 accept → receive를 몰 때만 씀)
  @visibleForTesting
  String? debugPushTokenFor(String transferId) => _incoming[transferId]?.token;

  // 암호화 전송이면 이 대화 링크의 복호화 함수를 반환함. 세션이 없는데 암호화 설정인 경우 평문으로 처리하지 않고 예외를 던짐
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
