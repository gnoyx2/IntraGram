part of '../vault.dart';

class VaultSnapshot {
  const VaultSnapshot({
    required this.settings,
    required this.conversations,
    required this.messages,
    required this.transfers,
  });

  final VaultSettings settings;
  final List<Conversation> conversations;
  final List<EphemeralMessage> messages;
  final List<FileTransfer> transfers;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': 1,
    'settings': settings.toJson(),
    'conversations': conversations.map((c) => c.toJson()).toList(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'transfers': transfers.map((t) => t.toJson()).toList(),
  };

  factory VaultSnapshot.fromJson(Map<String, dynamic> j) => VaultSnapshot(
    settings: VaultSettings.fromJson(
      (j['settings'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    ),
    conversations: _list(j['conversations'], Conversation.fromJson),
    messages: _list(j['messages'], EphemeralMessage.fromJson),
    transfers: _list(j['transfers'], FileTransfer.fromJson),
  );

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map>()
        .map((m) => fromJson(m.cast<String, dynamic>()))
        .toList();
  }
}
