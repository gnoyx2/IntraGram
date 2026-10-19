import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'in_memory_store_fixtures.dart';

// active_cleanup_*_test.dart가 공유하는 수신 정리 리그: 임시 폴더 하나에
// IncomingTransfers를 물리고 폴더 선택기(chooser)를 테스트가 쥐고
// 늦게 풀어줄 수 있게 함. 남은 .part 검사는 parts로 통일
// 정리 성공 여부는 모든 테스트가 await clear() 직후 teardown 전에
// 확인함 (teardown이 지운 파일이 clear()의 성공으로 보이지 않게)
class IncomingCleanupRig {
  late Directory dir;
  late InMemoryStore store;
  late TransferConcurrencyGate gate;
  late IncomingTransfers incoming;
  Completer<String?>? chooser;

  void setUp({int? maxConcurrent}) {
    dir = Directory.systemTemp.createTempSync('intragram_r2_active_');
    store = InMemoryStore()..upsertConversation(conversation('c'));
    chooser = null;
    build(maxConcurrent: maxConcurrent);
  }

  void build({int? maxConcurrent}) {
    gate = maxConcurrent == null
        ? TransferConcurrencyGate()
        : TransferConcurrencyGate(maxConcurrent: maxConcurrent);
    incoming = IncomingTransfers(
      store: store,
      linkFor: (_) => null,
      gate: gate,
      chooseDirectory: (_) => chooser?.future ?? Future.value(dir.path),
    );
  }

  Future<void> tearDown() async {
    store.dispose();
    await store.drainDisposals();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  FileTransfer offer(String id, {int size = 8, String attempt = 'a'}) =>
      FileTransfer(
        id: id,
        conversationId: 'c',
        direction: TransferDirection.incoming,
        fileName: '$id.bin',
        totalBytes: size,
        attemptId: attempt,
      );

  List<FileSystemEntity> parts() =>
      dir.listSync().where((e) => e.path.endsWith('.part')).toList();

  // accept 뒤 받는 쪽이 발급한 push 토큰으로 body 수신을 시작함
  Future<bool> startReceive(String id, Stream<List<int>> body) =>
      incoming.receive(
        transferId: id,
        attemptId: 'a',
        token: incoming.debugPushTokenFor(id)!,
        body: body,
        headerDeclaredSize: 8,
      );
}

// 이벤트 큐를 충분히 돌려서 비동기 착수(폴더 선택/예약)가 끝나게 함
Future<void> settle() => pumpEventQueue(times: 20);
