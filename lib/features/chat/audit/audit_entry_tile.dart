import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

class AuditEntryTile extends StatefulWidget {
  const AuditEntryTile({
    required this.evidence,
    required this.entry,
    super.key,
  });

  final EvidenceStore evidence;
  final EvidenceEntry entry;

  @override
  State<AuditEntryTile> createState() => _AuditEntryTileState();
}

class _AuditEntryTileState extends State<AuditEntryTile> {
  bool? _valid;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant AuditEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entry, widget.entry)) _valid = null;
  }

  Future<void> _verify() async {
    final e = widget.entry;
    final batch = e.batchNo == null ? null : widget.evidence.batch(e.batchNo!);
    final path = widget.evidence.proofFor(e);
    final generation = widget.evidence.generation;
    final valid =
        await e.attestation.verify() &&
        batch != null &&
        path != null &&
        verifyMerkleProof(
          leaf: e.leaf,
          index: e.batchIndex!,
          leafCount: batch.header.leafCount,
          path: path,
          root: batch.header.root,
        );
    if (mounted &&
        identical(e, widget.entry) &&
        generation == widget.evidence.generation) {
      setState(() => _valid = valid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final entry = widget.entry;
    final receipt = entry.attestation;
    final kind = switch (receipt.kind) {
      AttestationKind.deliveryCommitted => 'audit.delivery',
      AttestationKind.burnTriggered => 'audit.burn',
      AttestationKind.cleanupCompleted => 'audit.cleanup',
      AttestationKind.cleanupFailed => 'audit.cleanupFailed',
    };
    final batch = entry.batchNo == null
        ? null
        : widget.evidence.batch(entry.batchNo!);
    return ExpansionTile(
      key: ValueKey(receipt.eventId),
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      leading: Icon(
        entry.status == EvidenceStatus.rejected
            ? Icons.error_outline
            : Icons.receipt_long,
      ),
      title: Text(s.t(kind)),
      subtitle: Text(
        '${receipt.subjectId} · ${s.t(entry.status == EvidenceStatus.rejected ? 'audit.rejected' : 'audit.signedReceipt')}',
      ),
      childrenPadding: const EdgeInsets.all(AppSpacing.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded && batch != null) ...[
          Text(s.t('audit.proofMaterial')),
          SelectableText(
            jsonEncode({
              'salt': base64.encode(entry.leafSalt),
              'path': [
                for (final p in widget.evidence.proofFor(entry) ?? const [])
                  base64.encode(p),
              ],
            }),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _verify,
                child: Text(s.t('audit.verifyProof')),
              ),
              TextButton(
                onPressed: () => OsPrivacy.copySensitive(
                  exportAnchorBundle(
                    widget.evidence,
                    batch,
                    only: {receipt.eventId},
                  ),
                ),
                child: Text(s.t('audit.copyProof')),
              ),
            ],
          ),
        ],
        if (_valid != null)
          Text(s.t(_valid! ? 'audit.valid' : 'audit.invalid')),
        SelectableText(
          const JsonEncoder.withIndent('  ').convert(receipt.toWire()),
        ),
      ],
    );
  }
}
