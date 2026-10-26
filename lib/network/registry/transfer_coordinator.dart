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

// 보내기·받기를 묶음: 링크 종료·세션 초기화가 양쪽에 닿는 호출 하나가 됨
class TransferCoordinator {
  // 팩토리인 이유: 양쪽이 같은 게이트를 나눠 써야 하는데(합쳐서 kMaxConcurrentTransfers개) 초기화 리스트에선 서로를 못 봄
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

  // 1:1이면 그 대화 전송을 다 버리고, 방 멤버 링크면 peerKey로 그 멤버와 오간 것만 정리. 도는 I/O가 끝난 뒤에만 자원을 지움
  Future<void> handleLinkClosed(
    String conversationId, {
    String? peerKey,
  }) async {
    await outgoing.handleLinkClosed(conversationId, recipientKey: peerKey);
    await incoming.handleLinkClosed(conversationId, senderPeerId: peerKey);
  }

  // 세션 정리: 게이트부터 닫고 전송 전부를 도는 작업까지 기다려 잊음 (맵만 비우면 안 끝난 .part가 디스크에 남음)
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

  // 스토어에서 전송이 사라진 뒤(소각·와이프) 네트워크 쪽 남은 자원만 정리. 도는 I/O가 끝날 때까지 기다려서 패닉 경로가 정리 완료를 믿을 수 있음
  Future<void> discardTransfer(FileTransfer transfer) async {
    switch (transfer.direction) {
      case TransferDirection.outgoing:
        await outgoing.discard(transfer.id);
      case TransferDirection.incoming:
        await incoming.discard(transfer.id);
    }
  }
}
