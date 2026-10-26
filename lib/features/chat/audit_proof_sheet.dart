import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/features/chat/audit/audit_bundle_exchange.dart';
import 'package:intragram/features/chat/audit/audit_entry_tile.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

Future<void> showAuditProofSheet(
  BuildContext context,
  EvidenceStore evidence,
  AppIdentity identity,
) => showDialog<void>(
  context: context,
  builder: (_) => AuditProofSheet(evidence: evidence, identity: identity),
);

class AuditProofSheet extends StatefulWidget {
  const AuditProofSheet({
    required this.evidence,
    required this.identity,
    super.key,
  });

  final EvidenceStore evidence;
  final AppIdentity identity;

  @override
  State<AuditProofSheet> createState() => _AuditProofSheetState();
}

class _AuditProofSheetState extends State<AuditProofSheet> {
  bool _busy = false;

  Future<void> _seal() async {
    setState(() => _busy = true);
    try {
      await widget.evidence.seal();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DisplayFeatureSubScreen(child: Builder(builder: _dialog));
  }

  Widget _dialog(BuildContext context) {
    final s = S.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ListenableBuilder(
            listenable: widget.evidence,
            builder: (context, _) {
              final store = widget.evidence;
              return ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('audit.title'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: s.t('common.close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(s.t('audit.scope')),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _busy || !store.canSign || store.unbatched.isEmpty
                            ? null
                            : _seal,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(s.t('audit.seal')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AuditBundleExchange(
                            evidence: store,
                            identity: widget.identity,
                          ),
                        ),
                        icon: const Icon(Icons.import_export),
                        label: Text(s.t('audit.exchange')),
                      ),
                    ],
                  ),
                  if (store.entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Text(s.t('audit.empty')),
                    ),
                  for (final batch in store.batches.reversed)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.t('audit.batch', {
                                'n': '${batch.header.no}',
                                'count': '${batch.header.leafCount}',
                              }),
                            ),
                            SelectableText(
                              base64.encode(batch.header.root),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              s.t(
                                batch.anchor == null
                                    ? 'audit.anchorReady'
                                    : 'audit.anchored',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await OsPrivacy.copySensitive(
                                  exportAnchorBundle(store, batch),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: Text(s.t('audit.copyBundle')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final entry in store.entries.reversed)
                    AuditEntryTile(
                      key: ValueKey(entry.attestation.eventId),
                      evidence: store,
                      entry: entry,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
