import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/store/models.dart';
import 'org_credential_dialog.dart';

String orgStatusLabel(S s, OrgCredentialStatus? status) {
  if (status == null) return s.t('org.notPresented');
  if (!status.verified) {
    return s.t('org.rejected', {'reason': _checkLabel(s, status.check)});
  }
  if (DateTime.now().millisecondsSinceEpoch >= status.credential.expiresAtMs) {
    return s.t('org.expired');
  }
  // 공개 시드 발급기관은 누구나 같은 자격을 만들 수 있어서 배지 글에도 늘 '시연용'을 붙임
  return s.t('org.verified', {
    'issuer': status.demo ? s.t('org.demoIssuer') : status.issuerName ?? '',
    'org': status.credential.org,
    'role': status.credential.role,
    'snapshot': status.credential.snapshot,
  });
}

String _checkLabel(S s, OrgCheck check) => switch (check) {
  OrgCheck.verified => s.t('org.reason.verified'),
  OrgCheck.untrustedIssuer => s.t('org.reason.untrustedIssuer'),
  OrgCheck.invalidSignature => s.t('org.reason.invalidSignature'),
  OrgCheck.policyMismatch => s.t('org.reason.policyMismatch'),
  OrgCheck.revoked => s.t('org.reason.revoked'),
  OrgCheck.snapshotMismatch => s.t('org.reason.snapshotMismatch'),
  OrgCheck.expired => s.t('org.expired'),
  OrgCheck.notYetValid => s.t('org.reason.notYetValid'),
  OrgCheck.subjectMismatch => s.t('org.reason.subjectMismatch'),
  OrgCheck.invalidPop => s.t('org.reason.invalidPop'),
};

class OrgCredentialButton extends ConsumerWidget {
  const OrgCredentialButton({required this.conversation, super.key});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(inMemoryStoreProvider).orgCredentials;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final s = S.of(context);
        final status = book.statusOf(conversation.peerId);
        final verified =
            status != null &&
            status.verified &&
            DateTime.now().millisecondsSinceEpoch <
                status.credential.expiresAtMs;
        return IconButton(
          tooltip: conversation.isRoom
              ? s.t('org.title')
              : orgStatusLabel(s, status),
          icon: Icon(
            verified ? Icons.domain_verification : Icons.business_outlined,
            color: verified ? Theme.of(context).colorScheme.tertiary : null,
          ),
          onPressed: () => showOrgCredentialDialog(
            context,
            book: book,
            identity: ref.read(appIdentityProvider),
            peerIds: conversation.isRoom
                ? conversation.members.keys.toList()
                : [if (conversation.peerId != null) conversation.peerId!],
          ),
        );
      },
    );
  }
}
