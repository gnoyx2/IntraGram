import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';

import 'support/handshake_pair.dart';

void main() {
  test(
    'a verified auto-accept conversation fires the auto-accept hook',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      p.storeB.setLocalVerified('cB');
      p.storeB.setPeerVerified('cB');
      p.storeB.setConversationAutoAccept('cB', value: true);

      final autoAccepted = <String>[];
      p.linkB.onAutoAcceptOffer = autoAccepted.add;

      await p.linkA.sendFileOffer(
        transferId: 'f1',
        attemptId: 'a-f1',
        mode: 'push',
        name: 'report.pdf',
        size: 12,
        enc:
            true, // 프로덕션의 1:1 offer는 항상 enc=true (수신 쪽이 방이 아닌 대화의 enc=false를 거부함)
      );
      await pumpEventQueue(times: 60);

      expect(p.storeB.transfer('f1'), isNotNull);
      expect(autoAccepted, <String>['f1']);
    },
  );

  test('a conversation without auto-accept never fires the hook', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    final autoAccepted = <String>[];
    p.linkB.onAutoAcceptOffer = autoAccepted.add;

    await p.linkA.sendFileOffer(
      transferId: 'f2',
      attemptId: 'a-f2',
      mode: 'push',
      name: 'x.bin',
      size: 4,
      enc: true,
    );
    await pumpEventQueue(times: 60);

    expect(p.storeB.transfer('f2'), isNotNull, reason: 'offer still recorded');
    expect(autoAccepted, isEmpty);
  });

  test('a reaction crosses the encrypted link onto the peer copy', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    await p.linkA.sendText('lunch?', ttlSeconds: 0);
    await pumpEventQueue(times: 60);
    final id = chat(p.storeB, 'cB').single.id;

    await p.linkB.sendReaction(id, '👍', true);
    await pumpEventQueue(times: 60);

    expect(
      chat(p.storeA, 'cA').single.reactions.values.expand((s) => s),
      contains('👍'),
    );
  });

  test('a reply message carries the parent id across the link', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    await p.linkA.sendText('parent', ttlSeconds: 0);
    await pumpEventQueue(times: 60);
    final parentId = chat(p.storeA, 'cA').single.id;

    await p.linkA.sendText('child', ttlSeconds: 0, replyToId: parentId);
    await pumpEventQueue(times: 60);

    final onB = chat(p.storeB, 'cB').firstWhere((m) => m.text == 'child');
    expect(onB.replyToId, parentId);
  });

  test(
    'manual "delete for everyone" burns the peer copy with no timer',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      // LinkRegistry의 store.localBurns -> link.sendBurn 배선을 그대로 흉내냄
      p.storeA.localBurns.listen((e) => p.linkA.sendBurn(e.messageId));

      await p.linkA.sendText('wrong chat', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      final id = chat(p.storeA, 'cA').single.id;
      expect(chat(p.storeB, 'cB').single.id, id);

      p.storeA.userDeletesMessage(id); // 사용자가 길게 눌러 "모두에게서 삭제"
      await pumpEventQueue(times: 60);

      expect(chat(p.storeA, 'cA'), isEmpty, reason: 'gone locally');
      expect(chat(p.storeB, 'cB'), isEmpty, reason: 'burn frame reached B');
    },
  );
}
