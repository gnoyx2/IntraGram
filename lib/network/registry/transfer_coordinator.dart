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
  // 팩토리 생성자를 사용하는 이유: 송수신 양측이 동일한 게이트를 공유해야 하나 초기화 리스트에서는 새로 생성된 인스턴스를 공유할 수 없음
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

  // 1:1 대화면 해당 대화의 전송을 모두 정리하고, 그룹 방 멤버 링크면 peerKey로 해당 멤버와 연관된 항목만 정리함. 진행 중인 I/O 완료 후 자원을 해제함
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

  // 스토어에서 전송이 제거된 후(소각·와이프) 네트워크 계층의 잔여 자원만 정리함. 진행 중인 I/O 완료까지 대기하여 패닉 시 완전한 정리를 보장함
  Future<void> discardTransfer(FileTransfer transfer) async {
    switch (transfer.direction) {
      case TransferDirection.outgoing:
        await outgoing.discard(transfer.id);
      case TransferDirection.incoming:
        await incoming.discard(transfer.id);
    }
  }
}
