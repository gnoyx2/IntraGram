import 'package:flutter/material.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'org_credential_badge.dart' show orgStatusLabel;

Future<void> showOrgCredentialDialog(
  BuildContext context, {
  required OrgCredentialBook book,
  required AppIdentity identity,
  required List<String> peerIds,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _OrgCredentialDialog(book: book, identity: identity, peerIds: peerIds),
);

class _OrgCredentialDialog extends StatefulWidget {
  const _OrgCredentialDialog({
    required this.book,
    required this.identity,
    required this.peerIds,
  });
  final OrgCredentialBook book;
  final AppIdentity identity;
  final List<String> peerIds;

  @override
  State<_OrgCredentialDialog> createState() => _OrgCredentialDialogState();
}

class _OrgCredentialDialogState extends State<_OrgCredentialDialog> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final generation = widget.book.generation;
    final holder = widget.identity.peerId;
    final s = S.of(context);
    try {
      final credential = await issueDemoCredential(
        widget.identity,
        org: s.t('org.demoOrg'),
        dept: s.t('org.demoDept'),
        role: s.t('org.demoRole'),
      );
      if (!await credential.issuerSigned()) {
        throw StateError('issuer signature');
      }
      if (generation == widget.book.generation &&
          holder == widget.identity.peerId) {
        widget.book.activate(credential);
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _peerCredential(S s, String id) {
    final status = widget.book.statusOf(id);
    final credential = status?.credential;
    var label = '$id\n${orgStatusLabel(s, status)}';
    if (status?.verified == true && credential != null) {
      final expires = DateTime.fromMillisecondsSinceEpoch(
        credential.expiresAtMs,
      ).toLocal();
      label +=
          '\n${credential.dept} · ${credential.policy}\n'
          '${s.t('org.expires')}: $expires';
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SelectableText(label),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.book,
    builder: (context, _) {
      final s = S.of(context);
      final own = widget.book.holderFor(widget.identity);
      return AppAlertDialog(
        cupertino: isCupertinoDialog(context),
        title: Text(s.t('org.title')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.t('org.demoNotice')),
                const SizedBox(height: AppSpacing.md),
                Text(s.t('org.localCredential')),
                SelectableText(
                  own == null
                      ? s.t('org.notPresented')
                      : '${own.org} · ${own.dept} · ${own.role}\n'
                            '${s.t('org.demoIssuer')}\n${own.policy} · ${own.snapshot}\n'
                            '${s.t('org.expires')}: '
                            '${DateTime.fromMillisecondsSinceEpoch(own.expiresAtMs).toLocal()}',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(s.t('org.peerCredentials')),
                for (final id in widget.peerIds) _peerCredential(s, id),
                if (_failed) Text(s.t('org.activationFailed')),
              ],
            ),
          ),
        ),
        actions: dialogActions(context, [
          AdaptiveDialogAction(
            cupertino: isCupertinoDialog(context),
            onPressed: () => Navigator.of(context).pop(),
            label: s.t('common.close'),
          ),
          if (own != null)
            AdaptiveDialogAction(
              cupertino: isCupertinoDialog(context),
              onPressed: _busy ? null : widget.book.deactivate,
              label: s.t('org.deactivate'),
            ),
          AdaptiveDialogAction(
            cupertino: isCupertinoDialog(context),
            emphasis: true,
            onPressed: _busy || widget.identity.publicKey == null
                ? null
                : _activate,
            label: s.t('org.activateDemo'),
          ),
        ]),
      );
    },
  );
}
