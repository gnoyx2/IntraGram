import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/fake_file_source_channel.dart';
import 'support/in_memory_store_fixtures.dart';

// 아무도 맡지 않게 된 native 소스(닫힌 세션에 뒤늦게 돌아온 피커
// 결과, 사라진 대화, 배치 도중 실패로 못 낸 나머지)는 바로 놓이고,
// 이미 stage된 소스는 teardown이 한 번만 놓음

// 지정한 번째 upsertTransfer에서 던지는 스토어 (배치 도중 실패를 흉내냄)
class _FlakyStore extends InMemoryStore {
  _FlakyStore(this.failOnUpsert);
  final int failOnUpsert;
  int _upserts = 0;

  @override
  void upsertTransfer(FileTransfer transfer) {
    if (++_upserts == failOnUpsert) throw StateError('store failed');
    super.upsertTransfer(transfer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFileSourceChannel fake;
  late InMemoryStore store;
  late LinkRegistry registry;

  LinkRegistry build(InMemoryStore s) => LinkRegistry(
    store: s,
    crypto: CryptoEngine(),
    identity: AppIdentity(peerId: 'a' * 32, alias: 'me', platform: 'test'),
  );

  Future<List<MobileFileSource>> pick(int count) {
    fake.pickCount = count;
    return MobileFileSource.pick();
  }

  setUp(() {
    fake = FakeFileSourceChannel()..install();
    store = InMemoryStore()..upsertConversation(conversation('c'));
    registry = build(store);
    addTearDown(() => store.dispose());
  });

  test('a pick that returns after teardown is released and never '
      'staged', () async {
    final picked = await pick(1);
    await registry.disposeAll();

    await registry.offerStreamSources('c', picked);

    expect(store.transfers, isEmpty);
    expect(fake.count('release:s1'), 1);
  });

  test('a conversation that vanished releases every source of the '
      'batch', () async {
    await registry.offerStreamSources('missing', await pick(3));

    expect(store.transfers, isEmpty);
    expect(fake.count('release:'), 3);
  });

  test('a mid-batch failure releases the sources never offered; the staged '
      'ones wait for teardown and are released once', () async {
    store = _FlakyStore(2)..upsertConversation(conversation('c'));
    registry = build(store);
    addTearDown(() => store.dispose());
    final picked = await pick(3);

    await expectLater(
      registry.offerStreamSources('c', picked),
      throwsStateError,
    );

    expect(fake.count('release:s3'), 1, reason: 'never offered → released now');
    expect(fake.count('release:s1'), 0, reason: 'staged, retryable');
    expect(fake.count('release:s2'), 0, reason: 'staged before the failure');

    await registry.disposeAll();

    expect(fake.count('release:s1'), 1);
    expect(fake.count('release:s2'), 1);
    expect(fake.count('release:s3'), 1, reason: 'idempotent, not doubled');
  });
}
