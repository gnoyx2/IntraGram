import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

VaultSnapshot snap({VaultSettings? settings}) => VaultSnapshot(
  settings: settings ?? const VaultSettings(enabled: true),
  conversations: [
    Conversation(
      id: 'c1',
      peerAlias: 'blue-otter-38',
      peerPlatform: 'macOS',
      transport: PeerTransport.app,
      startedAt: DateTime(2026, 1, 1),
      online: true,
      secure: true,
      localVerified: true,
      peerVerified: true,
      outgoingTtlSeconds: 30,
    ),
  ],
  messages: [
    EphemeralMessage(
      id: 'm1',
      conversationId: 'c1',
      direction: MessageDirection.incoming,
      kind: MessageKind.text,
      senderAlias: 'blue-otter-38',
      createdAt: DateTime(2026, 1, 1, 10),
      text: 'hello',
      ttlSeconds: 30,
      delivery: DeliveryState.sent,
    ),
  ],
  transfers: [
    const FileTransfer(
      id: 't1',
      conversationId: 'c1',
      direction: TransferDirection.incoming,
      fileName: 'photo.jpg',
      totalBytes: 2048,
      transferredBytes: 2048,
      localPath: '/tmp/photo.jpg',
      state: TransferState.complete,
    ),
  ],
);
