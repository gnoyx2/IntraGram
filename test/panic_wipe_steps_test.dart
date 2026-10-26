import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import 'support/in_memory_store_fixtures.dart';
import 'support/panic_fakes.dart';
import 'support/test_identities.dart';

// 패닉 시퀀스의 순서/타임아웃/admission 불변식: 각 정지 단계를 테스트가 Completer로
// 직접 쥐고 있어서 진짜 시간/플랫폼 채널에 안 기대고 결정적으로 돎

class _NoVault extends Vault {
  @override
  Future<bool> isEncrypted() async => false;
  @override
  Future<VaultSnapshot?> load({String? pin}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PanicSteps steps;
  late InMemoryStore store;
  late PanicRegistry registry;
  late ProviderContainer container;
  late AppIdentity identity;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_panic_');
    steps = PanicSteps();
    identity = testIdentity('a');
    store = InMemoryStore()..upsertConversation(conversation('c1'));
    registry = PanicRegistry(
      steps,
      store: store,
      chooseDirectory: (_) async => dir.path,
    );
    store.onTransferRemoved = registry.discardRemovedTransfer;
    container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(_NoVault()),
        serverControllerProvider.overrideWith(() => PanicServer(steps)),
      ],
    );
  });

  tearDown(() async {
    VoiceProducerRegistry.instance.reopenAdmission();
    container.dispose();
    store.dispose();
    await store.drainDisposals();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<PanicWipeResult> panic({
    Duration stepTimeout = const Duration(seconds: 5),
  }) => executePanicWipe(
    sweepTemp: () async => steps.calls.add('temp'),
    store: store,
    registry: registry,
    serverController: container.read(serverControllerProvider.notifier),
    foregroundService: PanicForeground(steps),
    notificationService: PanicNotifications(steps),
    vaultSettings: container.read(vaultSettingsProvider.notifier),
    vaultAccess: container.read(vaultAccessProvider.notifier),
    identityStore: IdentityStore(resolveDir: () async => dir.path),
    identity: identity,
    releaseNativeSources: () {
      steps.calls.add('native');
      return steps.native.future;
    },
    directorySettingsFile: File('${dir.path}/download_directories.json'),
    clearClipboard: () async => steps.calls.add('clipboard'),
    stepTimeout: stepTimeout,
  );

  test(
    'a foreground service that does not confirm stop is a failure',
    () async {
      steps
        ..voice.complete()
        ..notifications.complete()
        ..foreground.complete(false)
        ..server.complete()
        ..links.complete()
        ..native.complete();

      final result = await panic();

      expect(result.failures.map((f) => f.step), ['foregroundService']);
      expect(store.conversations, isEmpty);
    },
  );

  test(
    'voice producers starting during panic are stopped, then reopened',
    () async {
      final future = panic();
      await pumpEventQueue();

      var lateStopped = 0;
      VoiceProducerRegistry.instance.register(() async => lateStopped++);
      expect(lateStopped, 1, reason: 'admission is closed while panic runs');

      steps.completeAll();
      await future;

      var reopenedStopped = 0;
      VoiceProducerRegistry.instance.register(() async => reopenedStopped++);
      await VoiceProducerRegistry.instance.stopAll();
      expect(
        reopenedStopped,
        1,
        reason: 'admission reopens for the next session',
      );
    },
  );

  test('active receive: no transfer and no .part survive the panic', () async {
    steps.completeAll();
    registry.delegate = true;
    store.upsertTransfer(
      const FileTransfer(
        id: 't',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'a.bin',
        totalBytes: 8,
        attemptId: 'attempt',
      ),
    );
    await registry.acceptTransfer('t');
    final token = registry.debugIncoming.debugPushTokenFor('t')!;
    final body = StreamController<List<int>>();
    // 부하에서 파일 open이 늦으면 패닉이 구독보다 먼저 와서 body가 끝내 구독되지
    // 않을 수 있고, 아무도 listen하지 않은 컨트롤러의 close()는 영영 안 끝남
    addTearDown(() => unawaited(body.close()));
    final receiving = registry.debugIncoming.receive(
      transferId: 't',
      attemptId: 'attempt',
      token: token,
      body: body.stream,
      headerDeclaredSize: 8,
    );
    await pumpEventQueue();
    expect(store.transfer('t')!.state, TransferState.transferring);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isNotEmpty);

    final result = await panic();

    expect(result.isComplete, isTrue, reason: '${result.failures}');
    expect(await receiving, isFalse);
    expect(store.transfers, isEmpty);
    expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
  });
}
