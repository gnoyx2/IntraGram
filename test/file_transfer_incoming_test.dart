import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/registry/incoming_transfers.dart';
import 'package:intragram/network/registry/transfer_gate.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

void main() {
  group('IncomingTransfers — voice message auto-accept', () {
    test('pulls to RAM with no folder picker and lands complete', () async {
      final payload = List<int>.filled(4096, 3);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response
            ..statusCode = HttpStatus.ok
            ..add(payload);
          await req.response.close();
        }),
      );

      final store = InMemoryStore();
      addTearDown(store.dispose);
      var pickerCalls = 0;
      final incoming = IncomingTransfers(
        store: store,
        linkFor: (_) => null,
        gate: TransferConcurrencyGate(),
        chooseDirectory: (_) async {
          pickerCalls++;
          return null;
        },
      );

      store.upsertConversation(
        Conversation(
          id: 'c1',
          peerAlias: 'peer',
          peerPlatform: 'Linux',
          transport: PeerTransport.app,
          startedAt: DateTime.now(),
        ),
      );
      store.upsertTransfer(
        FileTransfer(
          id: 'vn1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'voice-note.m4a',
          totalBytes: payload.length,
          mimeType: 'audio/mp4',
          voice: true,
          srcHost: server.address.address,
          srcPort: server.port,
        ),
      );

      await incoming.accept('vn1');

      final t = store.transfer('vn1')!;
      expect(pickerCalls, 0);
      expect(t.state, TransferState.complete);
      expect(t.localPath, isNull);
      expect(t.voiceBytes, payload);
    });

    test('a voice offer with no source address fails cleanly', () async {
      final store = InMemoryStore();
      addTearDown(store.dispose);
      final incoming = IncomingTransfers(
        store: store,
        linkFor: (_) => null,
        gate: TransferConcurrencyGate(),
        chooseDirectory: (_) async => fail('picker must not be called'),
      );
      store.upsertConversation(
        Conversation(
          id: 'c1',
          peerAlias: 'peer',
          peerPlatform: 'Linux',
          transport: PeerTransport.app,
          startedAt: DateTime.now(),
        ),
      );
      store.upsertTransfer(
        const FileTransfer(
          id: 'vn2',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'voice-note.m4a',
          totalBytes: 10,
          voice: true,
        ),
      );

      await incoming.accept('vn2');

      expect(store.transfer('vn2')!.state, TransferState.failed);
    });

    test(
      'a voice offer over the RAM size cap is refused, not pulled',
      () async {
        final store = InMemoryStore();
        addTearDown(store.dispose);
        final incoming = IncomingTransfers(
          store: store,
          linkFor: (_) => null,
          gate: TransferConcurrencyGate(),
          chooseDirectory: (_) async => fail('picker must not be called'),
        );
        store.upsertConversation(
          Conversation(
            id: 'c1',
            peerAlias: 'peer',
            peerPlatform: 'Linux',
            transport: PeerTransport.app,
            startedAt: DateTime.now(),
          ),
        );
        store.upsertTransfer(
          FileTransfer(
            id: 'vn3',
            conversationId: 'c1',
            direction: TransferDirection.incoming,
            fileName: 'voice-note.m4a',
            totalBytes: kMaxVoiceNoteBytes + 1,
            voice: true,
            srcHost: '10.0.0.9',
            srcPort: 7890,
          ),
        );

        await incoming.accept('vn3');

        expect(store.transfer('vn3')!.state, TransferState.failed);
        expect(store.transfer('vn3')!.voiceBytes, isNull);
      },
    );
  });
}
