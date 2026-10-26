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
import 'package:intragram/store/vault.dart';

import 'support/in_memory_store_fixtures.dart';
import 'support/panic_fakes.dart';
import 'support/test_identities.dart';

// 패닉 시퀀스의 순서/타임아웃/예외 격리 불변식: 각 정지 단계를 테스트가 Completer로
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

  test('store is wiped only after every stop step has finished', () async {
    VoiceProducerRegistry.instance.register(() {
      steps.calls.add('voice');
      return steps.voice.future;
    });
    final future = panic();
    await pumpEventQueue();
    // 정지 단계 다섯 개는 동시에 시작함: 네이티브 해제는 그 뒤
    expect(
      steps.calls,
      unorderedEquals([
        'voice',
        'notifications',
        'foreground',
        'server',
        'links',
      ]),
    );
    expect(store.conversations, isNotEmpty);

    steps.completeAllExceptLinks();
    await pumpEventQueue();
    expect(store.conversations, isNotEmpty, reason: 'links still stopping');
    expect(steps.calls, isNot(contains('native')));

    steps.links.complete();
    await pumpEventQueue();
    expect(steps.calls.last, 'native');
    expect(store.conversations, isNotEmpty, reason: 'native release pending');

    steps.native.complete();
    final result = await future;
    expect(store.conversations, isEmpty);
    // RAM을 지운 뒤 클립보드, 전송이 끝난 뒤 플러그인 임시 사본
    expect(steps.calls.sublist(steps.calls.length - 2), ['clipboard', 'temp']);
    expect(result.isComplete, isTrue);
  });

  test('a hung stop step is a partial failure, not a success', () async {
    steps.completeAll();
    final hung = Completer<void>();
    VoiceProducerRegistry.instance.register(() => hung.future);

    final result = await panic(stepTimeout: const Duration(milliseconds: 50));

    expect(result.isComplete, isFalse);
    expect(result.failures.map((f) => f.step), ['voiceProducers']);
    expect(result.failures.single.timedOut, isTrue);
    expect(store.conversations, isEmpty, reason: 'wipe must still run');

    // 새 세션이 시작된 뒤 미완료 단계가 뒤늦게 끝나도 새 세션엔 손 못 댐
    store.upsertConversation(conversation('fresh'));
    hung.complete();
    await pumpEventQueue();
    expect(store.conversations.map((c) => c.id), ['fresh']);
    expect(store.messages('fresh'), isEmpty);
    expect(store.transfers, isEmpty);
  });

  test('a throwing step is recorded and the later steps still run', () async {
    final future = panic();
    await pumpEventQueue(); // 리스너가 붙은 뒤에 에러로 끝냄: 미처리 에러를 방지함
    steps
      ..voice.complete()
      ..foreground.complete(true)
      ..server.complete()
      ..links.complete()
      ..native.complete()
      ..notifications.completeError(StateError('boom'));
    final result = await future;

    expect(result.failures.map((f) => f.step), ['notifications']);
    expect(result.failures.single.timedOut, isFalse);
    expect(result.failures.single.error, isA<StateError>());
    expect(store.conversations, isEmpty);
  });
}
