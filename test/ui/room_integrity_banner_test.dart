import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/widgets/room_integrity_banner.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity.dart';

import '../support/test_identities.dart';

void main() {
  testWidgets('room conflict badge reacts without changing SAS state', (
    tester,
  ) async {
    final book = RoomIntegrityBook()..join('room', 'scope', [], host: 'host');
    addTearDown(book.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomIntegrityBanner(book: book, conversationId: 'room'),
        ),
      ),
    );
    expect(
      find.text('Author signatures · waiting for checkpoints'),
      findsOneWidget,
    );
    book.conflict('room');
    await tester.pump();
    expect(
      find.text('Conflict Detected · room integrity warning'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('real author equivocation updates the verified room banner', (
    tester,
  ) async {
    final author = testIdentity('a');
    final host = testPeerId('b');
    final book = RoomIntegrityBook()
      ..join('room', 'scope', [author.peerId], host: host);
    final source = RoomIntegrityBook()
      ..join('source', 'scope', [author.peerId], host: host);
    addTearDown(book.dispose);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomIntegrityBanner(book: book, conversationId: 'room'),
        ),
      ),
    );
    final wires = await tester.runAsync(() async {
      Future<Map<String, dynamic>> signed(String id, String text) async {
        final payload = InnerFrame.message(
          id: id,
          text: text,
          ttlSeconds: 0,
          timestampMs: 1,
        );
        final event = await RoomAuthorEvent.sign(
          author,
          roomId: 'scope',
          hostPeerId: host,
          counter: 1,
          previousHash: base64.encode(Uint8List(32)),
          payload: payload,
        );
        expect(await event.verify(payload), isTrue);
        return {...payload, ...event.toWire()};
      }

      return [
        await signed('first', 'first view'),
        await signed('conflicting', 'different view'),
      ];
    });
    await tester.runAsync(() async {
      expect(
        await source.observe('source', wires![0], actorId: author.peerId),
        isTrue,
      );
      expect(
        await book.observe('room', wires[0], actorId: author.peerId),
        isTrue,
      );
    });
    await tester.pump();
    expect(
      find.text('Author signatures · waiting for checkpoints'),
      findsOneWidget,
    );
    expect(
      book.observeCheckpoint(
        'room',
        source.checkpoint('source'),
        observerId: host,
      ),
      isTrue,
    );
    await tester.pump();
    expect(
      find.text('Observed author signatures verified · checkpoints observed'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      expect(
        await book.observe('room', wires![1], actorId: author.peerId),
        isFalse,
      );
    });
    await tester.pump();
    expect(
      find.text('Conflict Detected · room integrity warning'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
