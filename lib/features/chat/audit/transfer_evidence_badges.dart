import 'package:flutter/material.dart';

import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

class TransferEvidenceBadges extends StatelessWidget {
  const TransferEvidenceBadges({
    required this.evidence,
    required this.transferId,
    super.key,
  });

  final EvidenceStore evidence;
  final String transferId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: evidence,
    builder: (context, _) {
      final receipts = evidence
          .forTransfer(transferId)
          .where(
            (e) =>
                e.attestation.kind == AttestationKind.deliveryCommitted &&
                e.status != EvidenceStatus.rejected,
          )
          .toList();
      if (receipts.isEmpty) return const SizedBox.shrink();
      final batched = receipts.any(
        (e) => e.batchNo != null && evidence.batch(e.batchNo!) != null,
      );
      final anchored = receipts.any(
        (e) => e.batchNo != null && evidence.batch(e.batchNo!)?.anchor != null,
      );
      return Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final key in [
            'audit.signature',
            if (batched) 'audit.inBatch',
            if (anchored) 'audit.anchored',
          ])
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.check, size: 14),
              label: Text(
                S.of(context).t(key),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      );
    },
  );
}
