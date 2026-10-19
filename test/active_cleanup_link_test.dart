import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/store/models.dart';

import 'support/incoming_cleanup_rig.dart';

// 직접 pull이 예약한 partial, 링크 종료가 건드리는 범위, 지우지 못한 partial의
// 보고 (활성 수신/취소/gate 대기는 active_cleanup_test.dart)
void main() {
  final rig = IncomingCleanupRig();
  setUp(rig.setUp);
  tearDown(rig.tearDown);

  test('a direct pull in flight is drained and its part removed', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final stalled = Completer<void>();
    unawaited(
      server.forEach((req) async {
        try {
          req.response.add(List<int>.filled(3, 1)); // 3/8바이트만 주고 멈춤
          await req.response.flush();
          await stalled.future;
          await req.response.close();
        } on Object {
          // 클라이언트가 먼저 끊는 게 의도된 상황
        }
      }),
    );
    rig.store.upsertTransfer(
      FileTransfer(
        id: 'p',
        conversationId: 'c',
        direction: TransferDirection.incoming,
        fileName: 'p.bin',
        totalBytes: 8,
        attemptId: 'a',
        srcHost: server.address.address,
        srcPort: server.port,
        pullToken: 'tok',
        mode: FileTransferMode.pull,
      ),
    );
    final accepting = rig.incoming.accept('p');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(rig.parts(), hasLength(1), reason: 'the pull reserved a part');

    await rig.incoming.clear();

    expect(rig.parts(), isEmpty);
    stalled.complete();
    await accepting;
    expect(rig.parts(), isEmpty);
  });

  test('a link closing only touches its own sender', () async {
    rig.store
      ..upsertTransfer(rig.offer('mine'))
      ..upsertTransfer(rig.offer('theirs'));
    await rig.incoming.accept('mine');
    await rig.incoming.accept('theirs');
    expect(rig.parts(), hasLength(2));
    // 'mine'의 발신자를 m1로 표시해 둔 뒤 그 발신자의 링크만 닫음
    rig.store.upsertTransfer(
      FileTransfer(
        id: 'mine',
        conversationId: 'c',
        direction: TransferDirection.incoming,
        fileName: 'mine.bin',
        totalBytes: 8,
        attemptId: 'a',
        state: TransferState.accepted,
        senderPeerId: 'm1',
      ),
    );
    await rig.incoming.handleLinkClosed('c', senderPeerId: 'm1');
    expect(rig.parts(), hasLength(1), reason: 'only the closed sender cleaned');
    await rig.incoming.clear();
    expect(rig.parts(), isEmpty);
  });

  test(
    'a failed background cleanup is reported, then retried and resolved by clear',
    () async {
      rig.store.upsertTransfer(rig.offer('t'));
      await rig.incoming.accept('t');
      Process.runSync('chmod', ['555', rig.dir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', rig.dir.path]));

      rig.incoming.cancelTransfer('t'); // 배경 정리가 삭제를 시도하지만 거부당함
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(rig.parts(), hasLength(1), reason: 'the delete was refused');

      await expectLater(
        rig.incoming.clear(),
        throwsA(isA<TransferCleanupException>()),
      );
      expect(rig.parts(), hasLength(1), reason: 'still owned, not forgotten');

      Process.runSync('chmod', ['755', rig.dir.path]);
      await rig.incoming.clear(); // 소유 목록에 남아 있던 partial을 다시 시도해 치움

      expect(rig.parts(), isEmpty);
    },
    skip: Platform.isWindows ? 'chmod-based failure injection' : false,
  );

  test(
    'a partial that cannot be deleted is reported, never hidden',
    () async {
      rig.store.upsertTransfer(rig.offer('t'));
      await rig.incoming.accept('t');
      // 읽기 전용 디렉터리로 File.delete를 권한 거부로 실패시킴
      Process.runSync('chmod', ['555', rig.dir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', rig.dir.path]));

      await expectLater(
        rig.incoming.clear(),
        throwsA(isA<TransferCleanupException>()),
      );
      expect(rig.parts(), hasLength(1), reason: 'not silently forgotten');
    },
    skip: Platform.isWindows ? 'chmod-based failure injection' : false,
  );
}
