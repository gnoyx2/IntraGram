import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

// 보안 회귀 테스트: 결함이 되살아나면 실패함
void main() {
  late Directory dir;
  late InMemoryStore store;
  late IncomingTransfers incoming;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_transfer_');
    store = InMemoryStore();
    store.upsertConversation(
      Conversation(
        id: 'c',
        peerAlias: 'peer',
        peerPlatform: 'test',
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
      ),
    );
    store.upsertTransfer(
      const FileTransfer(
        id: 't',
        conversationId: 'c',
        direction: TransferDirection.incoming,
        fileName: 'tiny.bin',
        totalBytes: 8,
        attemptId: 'attempt',
      ),
    );
    incoming = IncomingTransfers(
      store: store,
      linkFor: (_) => null,
      gate: TransferConcurrencyGate(),
      chooseDirectory: (_) async => dir.path,
    );
  });
  tearDown(() async {
    store.dispose();
    await store.drainDisposals();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('short plain EOF must fail', () async {
    await expectLater(
      FileStreamer.receive(
        body: Stream.value(<int>[1, 2, 3, 4]),
        transferId: 't',
        attemptId: 'attempt',
        destinationPath: '${dir.path}/short.part',
        declaredSize: 8,
      ),
      throwsA(anything),
    );
  });

  test('missing complete AEAD record must fail', () async {
    final engine = CryptoEngine();
    final a = await engine.createSession();
    final b = await engine.createSession();
    addTearDown(a.destroy);
    addTearDown(b.destroy);
    await a.completeHandshake(b.publicKeyBase64);
    await b.completeHandshake(a.publicKeyBase64);
    await expectLater(
      decryptChunks(
        const Stream<List<int>>.empty(),
        b.openBytes,
        transferId: 't',
        attemptId: 'attempt',
        totalBytes: 8,
      ).toList(),
      throwsA(anything),
    );
  });

  test('bad token must preserve authorized upload slot', () async {
    await incoming.accept('t');
    final token = incoming.debugPushTokenFor('t');
    expect(token, isNotNull);
    expect(
      await incoming.receive(
        transferId: 't',
        attemptId: 'attempt',
        token: 'wrong',
        body: const Stream.empty(),
        headerDeclaredSize: 8,
      ),
      isFalse,
    );
    expect(incoming.debugPushTokenFor('t'), token);
  });

  test('smaller upload header must not redefine offer size', () async {
    await incoming.accept('t');
    final token = incoming.debugPushTokenFor('t')!;
    expect(
      await incoming.receive(
        transferId: 't',
        attemptId: 'attempt',
        token: token,
        headerDeclaredSize: 4,
        body: Stream.value(<int>[1, 2, 3, 4]),
      ),
      isFalse,
    );
  });

  test('registry teardown then wipe must remove owned partial', () async {
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: AppIdentity(peerId: 'a' * 32, alias: 'self', platform: 'test'),
      chooseDirectory: (_) async => dir.path,
    );
    store.onTransferRemoved = registry.discardRemovedTransfer;
    await registry.acceptTransfer('t');
    expect(dir.listSync(), hasLength(1));
    await registry.disposeAll();
    store.secureWipe();
    await store.drainDisposals();
    expect(dir.listSync(), isEmpty);
  });

  test('stalled incoming body cancellation must finish promptly', () async {
    final listening = Completer<void>();
    final body = StreamController<List<int>>(onListen: listening.complete);
    final token = CancelToken();
    final future = FileStreamer.receive(
      body: body.stream,
      transferId: 't',
      attemptId: 'attempt',
      destinationPath: '${dir.path}/cancel.part',
      declaredSize: 8,
      cancelToken: token,
    );
    final observed = future.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    // 받는 쪽이 멈춘 바디를 실제로 구독해 청크를 기다릴 때 취소해야 이 상황임. 이벤트 큐를 몇 번
    // 도는 걸로는 부하에서 파일 open이 안 끝났을 수 있고, 그러면 구독도 안 한 바디를 아래에서
    // 닫다가 영영 멈춤
    await listening.future.timeout(const Duration(seconds: 10));
    token.cancel();
    // 생산자는 계속 멈춰 있음. 취소는 다음 청크나 stall 타임아웃(25s)을 안 기다리고 끝나야 함 (무시하면 25s 뒤에야 끝나서 아래 상한에 걸림).
    // 정리(close·delete)의 파일 IO는 부하가 걸리면 수백 ms씩 걸리기도 해서(부하 중 60회에 1회 886ms) 고정 250ms 상한은 코드가 아니라 기계 부하를 재고 있었음
    final outcome = await observed.timeout(
      const Duration(seconds: 10),
      onTimeout: () => 'still waiting for the stalled producer',
    );
    // 테스트 자체는 생산자를 닫아 정리함. 영구 대기 작업을 남기지 않음
    await body.close();
    await observed;
    expect(outcome, isA<TransferCancelledException>());
  });
}
