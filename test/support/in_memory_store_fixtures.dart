import 'package:intragram/store/models.dart';

Conversation conversation(String id) => Conversation(
  id: id,
  peerAlias: 'peer',
  peerPlatform: 'Linux',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
);

EphemeralMessage incoming(String id, {int ttl = 0}) => EphemeralMessage(
  id: id,
  conversationId: 'c1',
  direction: MessageDirection.incoming,
  kind: MessageKind.text,
  senderAlias: 'peer',
  createdAt: DateTime(2026, 1, 1),
  text: 'secret',
  ttlSeconds: ttl,
  delivery: DeliveryState.sent,
);
