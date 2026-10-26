import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/boxed_list.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/readable_list.dart';

// 라이브 스토어를 안 거치고 디스크 스냅샷을 직접 읽어서 지금 파일에 뭐가 남았는지 보여 줌
// (홈 목록은 라이브와 보관 대화가 섞여서 저장된 것만 보고 지우기가 안 됨). 탭하면 기존 ChatRoomScreen을 엶
// (보관이 켜진 동안엔 이미 라이브 스토어에 올라와 있음)
class SavedChatsScreen extends ConsumerStatefulWidget {
  const SavedChatsScreen({super.key});

  @override
  ConsumerState<SavedChatsScreen> createState() => _SavedChatsScreenState();
}

class _SavedChatsScreenState extends ConsumerState<SavedChatsScreen> {
  late Future<VaultSnapshot?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(vaultProvider).load();
  }

  void _reload() => setState(() => _future = ref.read(vaultProvider).load());

  Future<void> _delete(Conversation conversation) async {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        cupertino: cupertino,
        title: Text(s.t('savedChats.deleteTitle')),
        content: Text(
          s.t('savedChats.deleteBody', {'name': s.title(conversation)}),
        ),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('savedChats.delete'),
          ),
        ]),
      ),
    );
    if (ok != true) return;

    final vault = ref.read(vaultProvider);
    final snapshot = await vault.load();
    if (snapshot == null) return;
    await vault.save(
      VaultSnapshot(
        settings: snapshot.settings,
        conversations: snapshot.conversations
            .where((c) => c.id != conversation.id)
            .toList(),
        messages: snapshot.messages
            .where((m) => m.conversationId != conversation.id)
            .toList(),
        transfers: snapshot.transfers
            .where((t) => t.conversationId != conversation.id)
            .toList(),
      ),
    );
    // 라이브 스토어에도 올라와 있으면 거기서도 지움 (안 그러면 지웠는데 목록엔 그대로 보임)
    ref.read(inMemoryStoreProvider).wipeConversation(conversation.id);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('savedChats.title'))),
      body: FutureBuilder<VaultSnapshot?>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final conversations =
              snap.data?.conversations ?? const <Conversation>[];
          if (conversations.isEmpty) {
            return EmptyState(
              art: EmptyStateArt.bubbles,
              title: s.t('savedChats.emptyTitle'),
              body: s.t('savedChats.emptyBody'),
            );
          }
          return ReadableList(
            children: [
              BoxedList(
                children: [
                  for (final c in conversations)
                    ListTile(
                      title: Text(s.title(c)),
                      subtitle: Text(_stamp(c.startedAt)),
                      onTap: () => openChat(context, c.id),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: s.t('savedChats.delete'),
                        onPressed: () => _delete(c),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _stamp(DateTime t) {
    final l = t.toLocal();
    final mm = l.month.toString().padLeft(2, '0');
    final dd = l.day.toString().padLeft(2, '0');
    return '${l.year}-$mm-$dd';
  }
}
