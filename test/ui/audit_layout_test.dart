import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/transfer_tile.dart';
import 'package:intragram/features/chat/widgets/org_credential_badge.dart';
import 'package:intragram/features/chat/widgets/room_member_list_dialog.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/features/chat/audit/audit_bundle_exchange.dart';
import 'package:intragram/features/chat/audit_proof_sheet.dart';
import 'package:intragram/l10n/strings.dart';

import '../support/test_identities.dart';
import '_harness.dart';

void main() {
  for (final lang in AppLang.values) {
    testWidgets('audit dialogs scroll at 3x text on a narrow screen ($lang)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final evidence = EvidenceStore()..bindSigner(testIdentity('a'));
      addTearDown(evidence.close);
      final s = S(lang);
      Future<void> open(Widget child) => tester.pumpWidget(
        MaterialApp(
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: LocaleScope(lang: lang, child: widget!),
          ),
          home: child,
        ),
      );
      await open(
        AuditProofSheet(evidence: evidence, identity: testIdentity('a')),
      );
      await tester.scrollUntilVisible(
        find.text(s.t('audit.empty')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await open(
        AuditBundleExchange(evidence: evidence, identity: testIdentity('a')),
      );
      await tester.scrollUntilVisible(
        find.text(s.t('audit.attach')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 375.0, 840.0]) {
    for (final lang in AppLang.values) {
      testWidgets('audit composite layouts fit $width pt ($lang)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = Harness();
        addTearDown(h.dispose);
        final peer = testIdentity('b');
        final credential = (await tester.runAsync(
          () => issueDemoCredential(
            peer,
            org: 'Research Institute With A Long Organization Name',
            dept: 'Engineering',
            role: 'Security reviewer',
          ),
        ))!;
        h.store.orgCredentials.record(
          peer.peerId,
          OrgCredentialStatus(
            check: OrgCheck.verified,
            credential: credential,
            issuerName: 'Demo issuer',
            demo: true,
          ),
          owner: Object(),
        );
        final room = Conversation(
          id: 'c1',
          peerAlias: 'Research room',
          peerPlatform: 'Room',
          transport: PeerTransport.app,
          startedAt: DateTime(2026),
          online: true,
          secure: true,
          isRoom: true,
          members: {
            peer.peerId: const RoomMember(alias: 'Member with a long name'),
          },
        );
        h.store
          ..upsertConversation(room)
          ..upsertTransfer(
            const FileTransfer(
              id: 't1',
              conversationId: 'c1',
              direction: TransferDirection.incoming,
              fileName: 'a-long-audit-report.pdf',
              totalBytes: 2048,
            ),
          )
          ..addMessage(
            msg(
              id: 'file1',
              dir: MessageDirection.incoming,
              kind: MessageKind.file,
              transferId: 't1',
            ),
          );
        h.store.evidence.bindSigner(testIdentity('a'));
        await tester.runAsync(
          () => h.store.evidence.issue(
            AttestationDraft(
              kind: AttestationKind.deliveryCommitted,
              subjectId: 't1',
              attemptId: 'attempt1',
              commitment: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
              policy: 'delivery/file-commit',
              outcome: 'committed',
            ),
            transferId: 't1',
          ),
        );
        await tester.pumpWidget(
          h.wrap(
            const ChatRoomScreen(conversationId: 'c1'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: LocaleScope(lang: lang, child: child!),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(OrgCredentialButton), findsOneWidget);
        expect(find.byType(TransferTile), findsOneWidget);
        expect(find.text('a-long-audit-report.pdf'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final context = tester.element(find.byType(ChatRoomScreen));
        showRoomMemberListDialog(
          context,
          room,
          orgCredentials: h.store.orgCredentials,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsOneWidget);
        expect(find.textContaining('Security reviewer'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        showAuditProofSheet(context, h.store.evidence, testIdentity('a'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(S(lang).t('audit.delivery')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(AuditProofSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text(S(lang).t('audit.delivery')), findsOneWidget);
        h.store.orgCredentials.clear();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
