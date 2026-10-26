import 'package:flutter/material.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/room_integrity.dart';
import 'package:intragram/theme/tokens.dart';

class RoomIntegrityBanner extends StatelessWidget {
  const RoomIntegrityBanner({
    required this.book,
    required this.conversationId,
    super.key,
  });

  final RoomIntegrityBook book;
  final String conversationId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: book,
    builder: (context, _) {
      final status = book.status(conversationId);
      final conflict = status == RoomIntegrityStatus.conflict;
      final theme = Theme.of(context);
      final color = conflict
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant;
      final s = S.of(context);
      final label = s.t(switch (status) {
        RoomIntegrityStatus.waiting => 'roomIntegrity.waiting',
        RoomIntegrityStatus.verified => 'roomIntegrity.verified',
        RoomIntegrityStatus.conflict => 'roomIntegrity.conflict',
      });
      return Semantics(
        liveRegion: conflict,
        child: Container(
          width: double.infinity,
          color: conflict
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                conflict ? Icons.gpp_bad_outlined : Icons.fact_check_outlined,
                size: MediaQuery.textScalerOf(context).scale(18),
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
