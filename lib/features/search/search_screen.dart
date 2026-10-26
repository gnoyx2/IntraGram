import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/readable_list.dart';

// RAM에 있는 텍스트 메시지만 찾음. 보관이 켜져 있으면 지난 세션 기록도 RAM에 올라와 있어서 같이 잡힘
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  // 이름이 있어야 단축키가 같은 화면을 두 번 쌓지 않음
  static Route<void> route() => MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'search'),
    builder: (_) => const SearchScreen(),
  );

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(inMemoryStoreProvider);
    final vaultOn = ref.watch(vaultSettingsProvider).enabled;
    final trimmed = _query.trim();

    final grouped = <String, List<EphemeralMessage>>{};
    if (trimmed.isNotEmpty) {
      for (final hit in store.searchMessages(trimmed)) {
        grouped.putIfAbsent(hit.conversationId, () => []).add(hit.message);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          enableIMEPersonalizedLearning: false,
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.of(context).t('home.searchMessages'),
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: trimmed.isEmpty
          ? _EmptyHint(vaultOn: vaultOn)
          : grouped.isEmpty
          ? EmptyState(
              art: EmptyStateArt.magnifier,
              title: S.of(context).t('empty.searchNoResultsTitle'),
              body: S.of(context).t('empty.searchNoResultsBody'),
            )
          : ReadableList(
              children: [
                for (final entry in grouped.entries)
                  _ConversationGroup(
                    conversationId: entry.key,
                    matches: entry.value,
                  ),
              ],
            ),
    );
  }
}

class _ConversationGroup extends ConsumerWidget {
  const _ConversationGroup({
    required this.conversationId,
    required this.matches,
  });

  final String conversationId;
  final List<EphemeralMessage> matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId));
    final title = conversation == null
        ? S.of(context).t('search.conversation')
        : S.of(context).title(conversation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xs,
          ),
          child: Text(
            '$title · ${matches.length}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final message in matches)
          ListTile(
            dense: true,
            title: Text(
              message.text ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_stamp(context, message.createdAt)),
            onTap: conversation == null
                ? null
                : () => openChat(context, conversationId),
          ),
      ],
    );
  }

  // 대화의 날짜 구분선과 같은 로캘별 날짜 (해가 바뀌면 연도까지)
  static String _stamp(BuildContext context, DateTime t) {
    final s = S.of(context);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    return '${s.dayLabel(t)} ${s.clock(t, use24h: use24h)}';
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.vaultOn});

  final bool vaultOn;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      art: EmptyStateArt.magnifier,
      title: S.of(context).t('empty.searchTitle'),
      body: S
          .of(context)
          .t(vaultOn ? 'search.emptyVaultOn' : 'search.emptyVaultOff'),
    );
  }
}
