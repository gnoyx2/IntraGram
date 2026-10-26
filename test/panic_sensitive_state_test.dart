import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/panic_fakes.dart';
import 'support/test_identities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('panic clears sensitive books before awaiting hung services and blocks '
      'new and in-flight evidence until final wipe', () async {
    final dir = Directory.systemTemp.createTempSync('panic_sensitive_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = testIdentity('a');
    final store = InMemoryStore();
    addTearDown(store.dispose);
    final steps = PanicSteps(); // 모든 중지 future는 처음에 완료되지 않고 대기함
    final registry = PanicRegistry(steps, store: store);
    store.evidence.bindSigner(identity);
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(PanicVault()),
        serverControllerProvider.overrideWith(() => PanicServer(steps)),
      ],
    );
    addTearDown(container.dispose);
    final draft = AttestationDraft(
      kind: AttestationKind.burnTriggered,
      subjectId: 'message',
      commitment: 'n4bQgYhMfWWaL+qgxVrQFaO/TxsrC4Is0V1sFbDwCgg=',
      policy: 'burn/delete-me',
      outcome: 'burned',
    );
    final signed = (await store.evidence.issue(draft))!;
    final batch = (await store.evidence.seal())!;
    store.evidence.witness(identity.peerId, batch.header);
    final credential = await issueDemoCredential(
      identity,
      org: 'Institute',
      dept: 'Research',
      role: 'Member',
    );
    store.orgCredentials
      ..activate(credential)
      ..record(
        identity.peerId,
        OrgCredentialStatus(check: OrgCheck.verified, credential: credential),
        owner: registry,
      );
    store.roomIntegrity.ensureRoom('room', host: identity.peerId);
    await store.roomIntegrity.sign('room', identity, {
      'id': 'message',
      'text': 'secret',
    });
    expect(store.evidence.entries, hasLength(1));
    expect(store.evidence.batches, hasLength(1));
    expect(store.evidence.witnessed, hasLength(1));
    expect(store.orgCredentials.holder, isNotNull);
    expect(store.roomIntegrity.retainedEvents('room'), 1);
    final signing = store.evidence.issue(draft);
    final generation = store.evidence.generation;

    var finished = false;
    final panic =
        executePanicWipe(
          store: store,
          registry: registry,
          serverController: container.read(serverControllerProvider.notifier),
          foregroundService: PanicForeground(steps),
          notificationService: PanicNotifications(steps),
          vaultSettings: container.read(vaultSettingsProvider.notifier),
          vaultAccess: container.read(vaultAccessProvider.notifier),
          identityStore: const PanicIdentityStore(),
          identity: identity,
          releaseNativeSources: () => steps.native.future,
          clearClipboard: () async {},
          sweepTemp: () async {},
          directorySettingsFile: File('${dir.path}/download_directories.json'),
        ).then((result) {
          finished = true;
          return result;
        });

    // executePanicWipe 호출 직후이며 아직 await나 이벤트 루프 틱이 돌지 않은 상태임
    expect(finished, isFalse);
    expect(steps.links.isCompleted, isFalse);
    expect(store.evidence.generation, greaterThan(generation));
    expect(store.evidence.canSign, isFalse);
    expect(store.evidence.entries, isEmpty);
    expect(store.evidence.batches, isEmpty);
    expect(store.evidence.witnessed, isEmpty);
    expect(store.orgCredentials.holder, isNull);
    expect(store.orgCredentials.statusOf(identity.peerId), isNull);
    expect(store.roomIntegrity.retainedEvents('room'), 0);
    expect(store.roomIntegrity.scope('room'), isNull);
    expect(await signing, isNull);
    expect(await store.evidence.issue(draft), isNull);
    store.evidence.record(signed, verified: true);
    store.evidence.witness(identity.peerId, batch.header);
    expect(store.evidence.entries, isEmpty);
    expect(store.evidence.witnessed, isEmpty);
    expect(await store.evidence.seal(), isNull);

    // 이전 중지 future가 대기 중인 동안 발생한 잔여 상태를 시뮬레이션함
    store.orgCredentials.activate(credential);
    store.roomIntegrity.ensureRoom('late', host: identity.peerId);
    steps.completeAll();
    expect((await panic).isComplete, isTrue);
    expect(store.orgCredentials.holder, isNull);
    expect(store.roomIntegrity.scope('late'), isNull);
    expect(store.evidence.entries, isEmpty);
    expect(store.evidence.canSign, isTrue, reason: 'next session can sign');
  });
}
