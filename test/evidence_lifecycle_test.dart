import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/in_memory_store_fixtures.dart';
import 'support/panic_fakes.dart';
import 'support/test_identities.dart';

// 소각·정리 진술은 저장소가 지우기 직전에 커밋먼트를 잡아 서명하고(본문은 증적에 안 남음), secureWipe·패닉은
// 증적을 먼저 비우고 늦게 끝난 서명·정리도 새 세션에 아무것도 못 남김

InMemoryStore _store() {
  final store = InMemoryStore()..upsertConversation(conversation('c1'));
  store.evidence.bindSigner(testIdentity('a'));
  addTearDown(store.dispose);
  return store;
}

FileTransfer _file(String id) => FileTransfer(
  id: id,
  conversationId: 'c1',
  direction: TransferDirection.incoming,
  fileName: 'plan.pdf',
  totalBytes: 9,
  state: TransferState.complete,
);

EphemeralMessage _fileMessage(String id) => EphemeralMessage(
  id: id,
  conversationId: 'c1',
  direction: MessageDirection.incoming,
  kind: MessageKind.file,
  senderAlias: 'peer',
  createdAt: DateTime(2026, 1, 1),
  transferId: id,
  delivery: DeliveryState.sent,
);

List<String> _policies(InMemoryStore s) => s.evidence.entries
    .where((e) => e.attestation.kind == AttestationKind.burnTriggered)
    .map((e) => e.attestation.policy)
    .toList();

void main() {
  test('a timer burn is attested from the record right before it is deleted '
      'and the attestation carries no body', () {
    fakeAsync((async) {
      final store = _store();
      final message = incoming('m1', ttl: 5);
      store.addMessage(message);
      store.markIncomingRead('c1');
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();

      expect(store.messageById('m1'), isNull);
      final entry = store.evidence.entries.firstWhere(
        (e) => e.attestation.kind == AttestationKind.burnTriggered,
      );
      expect(
        store.evidence.entries.last.attestation.policy,
        'cleanup/message-reference',
      );
      expect(entry.attestation.kind, AttestationKind.burnTriggered);
      expect(entry.attestation.policy, 'burn/ttl-read:5s');
      expect(entry.attestation.subjectId, 'm1');
      expect(jsonEncode(entry.attestation.toWire()), isNot(contains('secret')));
      // 소각·정리 진술은 같은 커밋먼트로 묶이고, salt는 버려서 본문을 맞힌 사람도 증적만으로 확인 못 함
      expect(
        store.evidence.entries.last.attestation.commitment,
        entry.attestation.commitment,
      );
      final guess = <Object?>[
        ...[kMessageCommitDomain, 'm1', 'text', 'secret', '', '', 0, ''],
        ...[message.createdAt.millisecondsSinceEpoch, 5],
      ];
      expect(
        entry.attestation.commitment,
        isNot(sha256B64(utf8.encode(jsonEncode(guess)))),
      );
    });
  });

  test('each burn path names its policy; replacing a failed bubble is not a '
      'burn', () async {
    final store = _store();
    for (final id in ['a', 'b', 'c', 'd']) {
      store.addMessage(incoming(id));
    }
    store.userDeletesMessage('a');
    store.burnMessage('b', cause: BurnCause.peerRequest);
    store.burnMessage('c');
    store.burnMessage('d', cause: BurnCause.replaced);
    await pumpEventQueue();
    expect(_policies(store), [
      'burn/delete-everyone',
      'burn/peer-request',
      'burn/delete-me',
    ]);
  });

  test('a burned file states when its app-managed resources were cleaned, '
      'or that cleaning failed', () async {
    final store = _store();
    var fail = false;
    store.onTransferRemoved = (_) async {
      if (fail) throw const FileSystemException('locked');
    };
    for (final id in ['f1', 'f2']) {
      store
        ..upsertTransfer(_file(id))
        ..addMessage(_fileMessage(id));
    }
    store.burnMessage('f1');
    await pumpEventQueue();
    fail = true;
    store.burnMessage('f2');
    await pumpEventQueue();
    final kinds = {
      for (final e in store.evidence.entries)
        '${e.attestation.subjectId}:${e.attestation.kind.name}',
    };
    expect(kinds, {
      'f1:burnTriggered',
      'f1:cleanupCompleted',
      'f2:burnTriggered',
      'f2:cleanupFailed',
    });
  });

  test('wiping a conversation states one cleanup for all of it', () async {
    final store = _store();
    store.onTransferRemoved = (_) async {};
    store
      ..addMessage(incoming('m1'))
      ..upsertTransfer(_file('f1'))
      ..addMessage(_fileMessage('f1'));
    store.wipeConversation('c1');
    await pumpEventQueue();
    final entry = store.evidence.entries.single;
    expect(entry.attestation.kind, AttestationKind.cleanupCompleted);
    expect(entry.attestation.policy, 'cleanup/conversation');
    expect(entry.attestation.subjectId, 'c1');
  });

  test(
    'a keyless store consumes failed cleanup without issuing evidence',
    () async {
      final store = InMemoryStore()..upsertConversation(conversation('c1'));
      addTearDown(store.dispose);
      store.onTransferRemoved = (_) async => throw StateError('locked');
      store
        ..upsertTransfer(_file('f1'))
        ..addMessage(_fileMessage('f1'));
      store.wipeConversation('c1');
      await pumpEventQueue();
      expect(store.evidence.entries, isEmpty);
    },
  );

  test('secureWipe empties the evidence at once and a cleanup that ends '
      'afterwards leaves nothing behind', () async {
    final store = _store();
    final release = Completer<void>();
    store.onTransferRemoved = (_) => release.future;
    store
      ..upsertTransfer(_file('f1'))
      ..addMessage(_fileMessage('f1'));
    store.burnMessage('f1');
    await pumpEventQueue();
    expect(_policies(store), ['burn/delete-me']);
    unawaited(store.evidence.seal());
    await pumpEventQueue();
    expect(store.evidence.batches, hasLength(1));

    store.secureWipe();
    expect(store.evidence.entries, isEmpty);
    expect(store.evidence.batches, isEmpty);
    release.complete();
    await pumpEventQueue();
    expect(store.evidence.entries, isEmpty, reason: 'late cleanup dropped');
  });

  test('a panic wipe ends with empty evidence without waiting on any '
      'signature', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('intragram_evidence_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final steps = PanicSteps()..completeAll();
    final store = _store();
    final registry = PanicRegistry(steps, store: store);
    store.evidence.bindSigner(testIdentity('a'));
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(PanicVault()),
        serverControllerProvider.overrideWith(() => PanicServer(steps)),
      ],
    );
    addTearDown(container.dispose);
    store.addMessage(incoming('m1'));
    store.burnMessage('m1');

    final result = await executePanicWipe(
      store: store,
      registry: registry,
      serverController: container.read(serverControllerProvider.notifier),
      foregroundService: PanicForeground(steps),
      notificationService: PanicNotifications(steps),
      vaultSettings: container.read(vaultSettingsProvider.notifier),
      vaultAccess: container.read(vaultAccessProvider.notifier),
      identityStore: IdentityStore(resolveDir: () async => dir.path),
      identity: testIdentity('a'),
      releaseNativeSources: () async {},
      clearClipboard: () async {},
      sweepTemp: () async {},
      directorySettingsFile: File('${dir.path}/download_directories.json'),
    );
    await pumpEventQueue();
    expect(result.isComplete, isTrue);
    expect(store.evidence.entries, isEmpty);
  });
}
