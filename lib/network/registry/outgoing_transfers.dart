import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/audit/content_commitment.dart' show sha256Tap;
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/core/path_safety.dart';
import 'package:intragram/core/secure_bytes.dart'
    show constantTimeEquals, generateSecureToken;
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

part 'outgoing_transfers_api.dart';
part 'outgoing_transfers_delivery.dart';
part 'outgoing_transfers_download.dart';
part 'outgoing_transfers_frames.dart';
part 'outgoing_transfers_offer.dart';
part 'outgoing_transfers_pull_body.dart';
part 'outgoing_transfers_receipt.dart';
part 'outgoing_transfers_recipients.dart';
part 'outgoing_transfers_relay.dart';
part 'outgoing_transfers_retry.dart';
part 'outgoing_transfers_thumb.dart';
part 'outgoing_file_source.dart';

// 보내는 절반: 고르거나 끌어 놓은 파일을 offer로 내고 수락되면 바이트를 흘림 (1:1은 push, 방·브라우저는 pull).
// 링크는 안 들고 매번 물어봄. 수신자별 상태가 따로라 한 명의 완료·거절·끊김이 다른 수신자를 안 건드림
class OutgoingTransfers {
  OutgoingTransfers({
    required this.store,
    required this.identity,
    required PeerLink? Function(String conversationId) linkFor,
    required this.gate,
    List<PeerLink> Function(String conversationId)? linksForTransfer,
    ({String host, int port})? Function()? localEndpoint,
    this.ackTimeout = kFileReceivedAckTimeout,
  })
    // 호출부에선 linkFor: 같은 이름이 더 잘 읽힘
    // ignore_for_file: prefer_initializing_formals
    : _linkFor = linkFor,
       _linksForTransfer =
           linksForTransfer ?? ((id) => [linkFor(id)].nonNulls.toList()),
       _localEndpoint = localEndpoint;

  final InMemoryStore store;
  final AppIdentity identity;
  final PeerLink? Function(String conversationId) _linkFor;

  // _linkFor의 여러 수신자판 (방이면 멤버 링크 전부)
  final List<PeerLink> Function(String conversationId) _linksForTransfer;

  // 받는 쪽과 나눠 쓰는 동시 전송 게이트
  final TransferConcurrencyGate gate;

  // 이 기기 서버의 사설 host:port (꺼져 있으면 null). pull offer에 찍어서 받는 쪽이 여기서 당겨 감
  final ({String host, int port})? Function()? _localEndpoint;

  // EOF 뒤 file_received ACK를 기다리는 시간 (테스트만 줄임)
  final Duration ackTimeout;

  final Map<String, OutgoingFileSource> _outgoing =
      <String, OutgoingFileSource>{};

  // clear가 세움: 늦게 온 제안(닫힌 세션에 돌아온 피커 결과 등)은 안 올리고 네이티브 자원만 놓음
  bool _closed = false;

  // 아직 도는 source 해제와 그 실패. clear가 끝까지 기다렸다가 실패는 던짐
  final Set<Future<void>> _pendingReleases = <Future<void>>{};
  final List<Object> _releaseFailures = <Object>[];
  final Map<String, Future<Object?>> _retiring = <String, Future<Object?>>{};

  // 테스트가 수신자별 상태(attempt/토큰/단계)를 직접 볼 때만 씀
  @visibleForTesting
  List<({String key, String attemptId, String? pullToken, String phase})>
  debugRecipients(String transferId) => [
    for (final r
        in _outgoing[transferId]?._recipients.values ??
            const <_OutgoingRecipient>[])
      (
        key: r.key,
        attemptId: r.attemptId,
        pullToken: r.pullToken,
        phase: r.phase.name,
      ),
  ];

  Future<void> offerInlineBytes(
    String conversationId,
    String name,
    Uint8List bytes, {
    String? mime,
    bool voice = false,
  }) async {
    final resolvedMime = mime ?? _mimeFor(name);
    final isImage = resolvedMime?.startsWith('image/') ?? false;
    await _offer(
      conversationId: conversationId,
      name: name,
      path: null,
      size: bytes.length,
      openStream: () => Stream<List<int>>.value(bytes),
      batchLabel: null,
      mime: resolvedMime,
      thumbFactory: isImage ? () => _imageThumb(bytes) : null,
      voice: voice,
      selfBytes: voice ? bytes : null,
    );
  }

  Future<void> _offer({
    required String conversationId,
    required String name,
    required String? path,
    required int size,
    required Stream<List<int>> Function() openStream,
    required String? batchLabel,
    String? batchId,
    String? mime,
    Future<String?> Function()? thumbFactory,
    String? preview,
    bool voice = false,
    Uint8List? selfBytes,
    Future<void> Function()? releaseSource,
  }) => _runOffer(
    this,
    conversationId: conversationId,
    name: name,
    path: path,
    size: size,
    openStream: openStream,
    batchLabel: batchLabel,
    batchId: batchId,
    mime: mime,
    thumbFactory: thumbFactory,
    preview: preview,
    voice: voice,
    selfBytes: selfBytes,
    releaseSource: releaseSource,
  );
}

// 링크의 수신자 키: 앱은 인증된 peerId, 브라우저 게스트는 링크마다 로컬 키 (wire엔 안 실림)
String recipientKeyOf(PeerLink link) =>
    link.remotePeerId ?? 'web:${identityHashCode(link)}';
