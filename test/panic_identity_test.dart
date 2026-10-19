import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/network/peer_auth.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/panic_fakes.dart';
import 'support/test_identities.dart';

// 패닉 소각이 신원 키를 갈아 끼우는지: 옛 시드는 0으로 덮이고 peerId가 바뀌며, 링크가 다 멈춘 뒤에만
// 바뀜(핸드셰이크 도중인 링크가 옛 키로 서명하다 어긋나지 않게). 나머지 순서 불변식은 panic_wipe_test
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PanicSteps steps;
  late InMemoryStore store;
  late ProviderContainer container;
  late AppIdentity identity;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_panic_id_');
    steps = PanicSteps();
    store = InMemoryStore();
    identity = testIdentity('a');
    container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(PanicVault()),
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

  Future<PanicWipeResult> panic({bool isDecoy = false}) => executePanicWipe(
    sweepTemp: () async {},
    store: store,
    registry: PanicRegistry(steps, store: store),
    serverController: container.read(serverControllerProvider.notifier),
    foregroundService: PanicForeground(steps),
    notificationService: PanicNotifications(steps),
    vaultSettings: container.read(vaultSettingsProvider.notifier),
    vaultAccess: container.read(vaultAccessProvider.notifier),
    identityStore: IdentityStore(resolveDir: () async => dir.path),
    identity: identity,
    isDecoySession: isDecoy,
    directorySettingsFile: File('${dir.path}/download_directories.json'),
    releaseNativeSources: () async {},
  );

  test('panic replaces the identity key and overwrites the old seed', () async {
    steps.completeAll();
    final oldPeerId = identity.peerId;
    final oldKey = identity.publicKey!;
    final oldSeed = identity.debugSeed!;
    expect(oldSeed.any((b) => b != 0), isTrue);

    final result = await panic();

    expect(result.isComplete, isTrue, reason: '${result.failures}');
    expect(identity.peerId, isNot(oldPeerId));
    expect(identity.publicKey, isNot(oldKey));
    expect(identity.peerId, peerIdOfKey(identity.publicKey!));
    expect(oldSeed.every((b) => b == 0), isTrue, reason: 'old key wiped');
    final signature = await identity.sign(<int>[1]);
    for (final (key, expected) in [
      (identity.publicKey!, true),
      (oldKey, false),
    ]) {
      expect(
        await verifyAuth(
          transcript: <int>[1],
          signature: signature,
          signerKey: key,
        ),
        expected,
        reason: 'the new key signs, the old one no longer does',
      );
    }
  });

  test('the identity key stays until every link has stopped', () async {
    final oldPeerId = identity.peerId;
    final future = panic();
    await pumpEventQueue();
    steps.completeAllExceptLinks();
    await pumpEventQueue();
    expect(identity.peerId, oldPeerId, reason: 'a link may still use it');

    steps.completeAll();
    await future;
    expect(identity.peerId, isNot(oldPeerId));
  });

  test('a decoy session replaces the identity key too', () async {
    steps.completeAll();
    final oldPeerId = identity.peerId;

    final result = await panic(isDecoy: true);

    expect(result.isComplete, isTrue, reason: '${result.failures}');
    expect(identity.peerId, isNot(oldPeerId));
  });
}
