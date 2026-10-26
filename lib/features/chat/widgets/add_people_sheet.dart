import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';

Future<void> showAddPeopleSheet(
  BuildContext context,
  WidgetRef ref,
  String conversationId,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _AddPeopleSheet(conversationId: conversationId),
  );
}

class _AddPeopleSheet extends ConsumerStatefulWidget {
  const _AddPeopleSheet({required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends ConsumerState<_AddPeopleSheet> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    // 이미 이 방에 있는 피어는 뺌: discovery는 멤버십을 몰라서 목록에 남는데, 다시 고르면
    // 연결 중복 거르기가 방 멤버는 안 봐서 소켓을 또 엶 (초대가 안 먹힌 것처럼 보임)
    final members = ref.watch(
      conversationProvider(widget.conversationId).select((c) => c?.members),
    );
    final peers = ref
        .watch(discoveryControllerProvider)
        .where((p) => !(members?.containsKey(p.peerId) ?? false))
        .toList();
    // 시트 전체가 스크롤됨: 작은 플로팅 창·큰 글씨에서 빈 상태 그림이나 버튼이 시트 밖으로 넘치지 않게
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(
            S.of(context).t('addPeople.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            S.of(context).t('addPeople.body'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (peers.isEmpty)
            EmptyState(
              art: EmptyStateArt.bubbles,
              title: S.of(context).t('empty.addPeopleTitle'),
              body: S.of(context).t('empty.addPeopleBody'),
            ),
          for (final peer in peers)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(peer.peerId),
              onChanged: (on) => setState(() {
                if (on ?? false) {
                  _picked.add(peer.peerId);
                } else {
                  _picked.remove(peer.peerId);
                }
              }),
              title: Text(peer.alias),
              subtitle: Text(peer.detail),
            ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () {
                    final chosen = peers
                        .where((p) => _picked.contains(p.peerId))
                        .toList();
                    ref
                        .read(linkRegistryProvider)
                        .addPeersToRoom(widget.conversationId, chosen);
                    Navigator.of(context).pop();
                  },
            child: Text(
              _picked.isEmpty
                  ? S.of(context).t('common.add')
                  : S.of(context).t('addPeople.add', {
                      'n': '${_picked.length}',
                    }),
            ),
          ),
        ],
      ),
    );
  }
}
