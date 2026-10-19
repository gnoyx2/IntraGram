import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/link_registry_fixtures.dart';

void main() {
  late InMemoryStore store;
  late Directory tmp;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    tmp = Directory.systemTemp.createTempSync('intragram_lr');
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
    tmp.deleteSync(recursive: true);
  });

  test(
    'deleteMessageForEveryone removes the message and signals a burn',
    () async {
      store.upsertConversation(conv('c1'));
      final burns = <String>[];
      final sub = store.localBurns.listen((e) => burns.add(e.messageId));
      store.addMessage(
        EphemeralMessage(
          id: 'gone1',
          conversationId: 'c1',
          direction: MessageDirection.outgoing,
          kind: MessageKind.text,
          senderAlias: 'me',
          createdAt: DateTime(2026, 1, 1),
          text: 'bye',
          delivery: DeliveryState.sent,
        ),
      );

      registry.deleteMessageForEveryone('gone1');
      await pumpEventQueue();

      expect(store.messages('c1'), isEmpty);
      expect(burns, <String>['gone1']);
      sub.cancel();
    },
  );

  test(
    'resendFailed replaces a failed text message with a fresh attempt',
    () async {
      store.upsertConversation(conv('c1'));
      // 살아있는 링크가 없으면 sendText가 시도를 실패로 기록함
      await registry.sendText('c1', 'hello?');
      final failed = store.messages('c1').single;
      expect(failed.delivery, DeliveryState.failed);

      registry.resendFailed(failed.id);
      await pumpEventQueue();

      final msgs = store.messages('c1');
      expect(
        msgs,
        hasLength(1),
        reason: 'old failed bubble removed, one new attempt',
      );
      expect(msgs.single.id, isNot(failed.id));
      expect(msgs.single.text, 'hello?');
    },
  );

  test('toggleReaction applies my reaction locally and toggles it off', () {
    store.upsertConversation(conv('c1'));
    store.addMessage(
      EphemeralMessage(
        id: 'm1',
        conversationId: 'c1',
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: 'peer',
        createdAt: DateTime(2026, 1, 1),
        text: 'hi',
        delivery: DeliveryState.sent,
      ),
    );

    registry.toggleReaction('c1', 'm1', '👍');
    expect(store.messageById('m1')!.reactions, {
      identity().peerId: {'👍'},
    });

    registry.toggleReaction('c1', 'm1', '👍'); // 같은 emoji라 해제
    expect(store.messageById('m1')!.reactions, isEmpty);
  });

  test('sendText threads the reply id onto the recorded message', () async {
    store.upsertConversation(conv('c1'));
    await registry.sendText('c1', 'agreed', replyToId: 'parent1');
    expect(store.messages('c1').single.replyToId, 'parent1');
  });

  test('inline mode records an oversized outbound message as failed', () async {
    store.upsertConversation(conv('c1'));
    store.largeMessageMode = LargeMessageMode.inline;

    await registry.sendText('c1', 'x' * (kMaxInlineMessageBytes + 10));

    expect(store.messages('c1').single.delivery, DeliveryState.failed);
  });

  test('spillToFile mode sends a long message as a .txt file offer', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );
    final id = store.conversations.single.id;
    store.largeMessageMode = LargeMessageMode.spillToFile;

    await registry.sendText(id, 'y' * (kSpillThresholdBytes + 100));
    await pumpEventQueue();

    final outgoing = store.transfers.singleWhere(
      (t) => t.direction == TransferDirection.outgoing,
    );
    expect(outgoing.fileName, 'message.txt');
    expect(outgoing.totalBytes, kSpillThresholdBytes + 100);
    expect(
      store.messages(id).any((m) => m.kind == MessageKind.text),
      isFalse,
      reason: 'the long text went out as a file, not an inline message',
    );
  });

  test('unlimited mode lets a huge message past the size gate', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );
    final id = store.conversations.single.id;
    store.largeMessageMode = LargeMessageMode.unlimited;

    await registry.sendText(id, 'z' * (kMaxInlineMessageBytes + 10));
    await pumpEventQueue();

    final m = store.messages(id).single;
    expect(m.kind, MessageKind.text);
    expect(m.delivery, isNot(DeliveryState.failed));
  });

  test('resendFailed ignores a message that is not a failed text', () async {
    store.upsertConversation(conv('c1'));
    store.addMessage(
      EphemeralMessage(
        id: 'ok1',
        conversationId: 'c1',
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: 'me',
        createdAt: DateTime(2026, 1, 1),
        text: 'sent fine',
        delivery: DeliveryState.sent,
      ),
    );
    registry.resendFailed('ok1');
    await pumpEventQueue();
    expect(store.messages('c1').single.id, 'ok1');
  });
}
