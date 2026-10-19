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
    // 이미 이 방(또는 대화)에 들어온 피어는 뺌. discovery는 방 멤버십을 몰라서 목록에 남는데,
    // 다시 고르면 LinkRegistry의 연결 dedupe가 활성 링크 맵만 보고 방 멤버 맵은 안 봐서
    // 새 소켓을 또 열어 "초대가 안 먹힘"처럼 보임
    final members = ref.watch(
      conversationProvider(widget.conversationId).select((c) => c?.members),
    );
    final peers = ref
        .watch(discoveryControllerProvider)
        .where((p) => !(members?.containsKey(p.peerId) ?? false))
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: peers
                      .map(
                        (peer) => CheckboxListTile(
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
                      )
                      .toList(),
                ),
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
      ),
    );
  }
}
