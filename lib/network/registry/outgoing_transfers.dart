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
part 'outgoing_transfers_recipients.dart';
part 'outgoing_transfers_relay.dart';
part 'outgoing_transfers_retry.dart';
part 'outgoing_transfers_thumb.dart';
part 'outgoing_file_source.dart';

// 파일 전송의 보내는 절반: 유저가 고르거나 드롭한 걸 file_offer로 바꾸고 피어가 수락하면
// 바이트를 스트리밍 (앱 피어엔 직접 push, 브라우저 게스트는 HTTP로 pull)
// _outgoing(staged source)만 소유하고 PeerLink는 안 들고 매번 _linkFor/_linksForTransfer에
// 물어봄. 수신자별 상태는 source의 recipient 맵에 있어서 한 수신자의 완료/거절/링크
// 종료가 다른 수신자의 상태를 지우지 않음
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
    // 호출부에서 linkFor:/linksForTransfer:/localEndpoint:가 this._...보다 잘 읽힘
    // ignore_for_file: prefer_initializing_formals
    : _linkFor = linkFor,
       _linksForTransfer =
           linksForTransfer ?? ((id) => [linkFor(id)].nonNulls.toList()),
       _localEndpoint = localEndpoint;

  final InMemoryStore store;
  final AppIdentity identity;
  final PeerLink? Function(String conversationId) _linkFor;

  // _linkFor의 다중 수신자판: 그룹 방이면 지금 붙어있는 멤버 링크
  // 전부, 1:1이면 _linkFor와 같은 걸 최대 한 개짜리 리스트로
  // 주입 안 되면(테스트 등) _linkFor 기반 fallback
  final List<PeerLink> Function(String conversationId) _linksForTransfer;

  // 동시 활성 전송 상한: TransferConcurrencyGate를 IncomingTransfers와 공유하는 인스턴스로 줌
  final TransferConcurrencyGate gate;

  // 이 기기 임베디드 서버의 사설 host:port (서버가 꺼져 있으면 null): pull
  // offer(그룹 방/음성)에 도장 찍어서 받는 쪽이 여기서 바이트를 직접 당기게 함
  final ({String host, int port})? Function()? _localEndpoint;

  // wire EOF 뒤 file_received ACK를 기다리는 시간: 프로덕션은 상수
  // 그대로, 테스트만 짧게 줄여 "ACK 없음은 timeout 뒤 실패"를 결정적으로 검사
  final Duration ackTimeout;

  final Map<String, OutgoingFileSource> _outgoing =
      <String, OutgoingFileSource>{};

  // clear가 admission을 닫으면 true: 그 뒤 늦게 도착한 제안(닫힌 세션에
  // 뒤늦게 돌아온 피커 결과 등)은 stage하지 않고 그 source의 native 자원만
  // 놓음
  // 레지스트리는 폐기 뒤 새로 만들어지니 다시 안 엶
  bool _closed = false;

  // 아직 도는 source release들(reader가 다 닫힌 뒤 fire-and-forget으로
  // 시작한 것)과 그 실패: clear가 끝까지 기다렸다가 실패는 삼키지 않고 던짐
  final Set<Future<void>> _pendingReleases = <Future<void>>{};
  final List<Object> _releaseFailures = <Object>[];

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

// PeerLink 하나가 수신자로서 갖는 키: 앱 피어는 인증된 peerId,
// peerId가 없는 브라우저 게스트는 링크 인스턴스별 로컬 합성 키
// (RAM 전용 라우팅 키일 뿐 wire에 안 실림)
String recipientKeyOf(PeerLink link) =>
    link.remotePeerId ?? 'web:${identityHashCode(link)}';
