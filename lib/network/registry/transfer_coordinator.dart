import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart' show kFileReceivedAckTimeout;
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

export 'package:intragram/network/registry/outgoing_transfers.dart'
    show OutgoingFileSource, OutgoingDownload;

// 보내기(outgoing)와 받기(incoming)를 묶는 seam: 링크가
// 닫히거나 세션이 초기화되는 게 양쪽에 다 닿는 호출 하나가 되고,
// 레지스트리가 필드 둘 대신 하나만 듦
class TransferCoordinator {
  // outgoing/incoming이 같은 TransferConcurrencyGate를 공유하게(합쳐서
  // kMaxConcurrentTransfers개까지) 팩토리로 먼저 만들어 넘김:
  // 생성자 초기화 리스트에선 두 필드가 서로의 값을 못 봄
  factory TransferCoordinator({
    required InMemoryStore store,
    required AppIdentity identity,
    required PeerLink? Function(String conversationId) linkFor,
    PeerLink? Function(FileTransfer transfer)? linkForTransfer,
    List<PeerLink> Function(String conversationId)? linksForTransfer,
    ({String host, int port})? Function()? localEndpoint,
    Future<String?> Function(String suggestedName)? chooseDirectory,
    Duration ackTimeout = kFileReceivedAckTimeout,
  }) {
    final gate = TransferConcurrencyGate();
    return TransferCoordinator._(
      gate: gate,
      outgoing: OutgoingTransfers(
        store: store,
        identity: identity,
        linkFor: linkFor,
        linksForTransfer: linksForTransfer,
        localEndpoint: localEndpoint,
        gate: gate,
        ackTimeout: ackTimeout,
      ),
      incoming: IncomingTransfers(
        store: store,
        linkFor: linkFor,
        linkForTransfer: linkForTransfer,
        chooseDirectory: chooseDirectory,
        gate: gate,
      ),
    );
  }

  TransferCoordinator._({
    required this.gate,
    required this.outgoing,
    required this.incoming,
  });

  final TransferConcurrencyGate gate;
  final OutgoingTransfers outgoing;
  final IncomingTransfers incoming;

  // 1:1이면 peerKey 없이 그 대화의 전송 전부 버림. 그룹 방의 멤버 링크 하나가 닫혔으면 peerKey(그
  // 멤버의 수신자 키)로 그 멤버와 오간 전송만 정리 (다른 멤버의 source/상태는 그대로)
  // 진행 중인 I/O가 있으면 실제로 끝날 때까지 기다린 뒤에만 소유 자원을 지움
  Future<void> handleLinkClosed(
    String conversationId, {
    String? peerKey,
  }) async {
    await outgoing.handleLinkClosed(conversationId, recipientKey: peerKey);
    await incoming.handleLinkClosed(conversationId, senderPeerId: peerKey);
  }

  // 세션 teardown: admission부터 차단(새 gate.acquire()
  // 즉시 거부)한 뒤 staged되고 수락된 전송 전부를 진행 중 작업까지 기다려
  // 잊음
  // (sync로 map만 비우면 안 끝난 전송의 소유 파셜이 dispose 이후에도 디스크에 남을 수 있음)
  Future<void> dispose() async {
    gate.close();
    // 한쪽 정리가 실패해도 다른 쪽은 끝까지 하고 실패는 그대로 던짐
    Object? failure;
    StackTrace? stack;
    for (final clear in <Future<void> Function()>[
      outgoing.clear,
      incoming.clear,
    ]) {
      try {
        await clear();
      } on Object catch (e, st) {
        failure ??= e;
        stack ??= st;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  // InMemoryStore.onTransferRemoved 훅이 부름: transfer가
  // 스토어에서 이미 사라진 뒤(소각/전체 와이프) 네트워크 쪽 남은 자원
  // (진행 중 취소 토큰, 스테이징된 source, 예약된 .part)만 정리. 진행 중이던 I/O가 있으면 끝날 때까지 기다려서
  // drainDisposals()를 부른 호출부(패닉 경로)가 실제 정리 완료를 보장받음
  Future<void> discardTransfer(FileTransfer transfer) async {
    switch (transfer.direction) {
      case TransferDirection.outgoing:
        await outgoing.discard(transfer.id);
      case TransferDirection.incoming:
        await incoming.discard(transfer.id);
    }
  }
}
