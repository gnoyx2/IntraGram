import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/file_transfer_crypto.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/transfer_rig.dart';

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'encrypted voice pull leaks no plaintext and decrypts to the exact bytes',
    () async {
      final rig = await TransferRig.create();
      final plain = Uint8List.fromList(
        List<int>.generate(65536, (i) => i % 251),
      )..setRange(0, 4, 'RIFF'.codeUnits);
      final t = await rig.offerVoice(plain);
      expect(t.encrypted, isTrue);
      expect(t.mode, FileTransferMode.pull);

      final res = await rig.get(t.id, rig.headers(t));

      expect(res.status, 200);
      expect(res.body, hasLength(encryptedFileLength(65536)));
      expect(res.length, encryptedFileLength(65536));
      expect(
        _contains(res.body, plain.sublist(0, 48)),
        isFalse,
        reason: 'no plaintext window may appear on the wire',
      );
      final decrypted = await decryptChunks(
        Stream<List<int>>.value(res.body),
        rig.remote.openFileChunk,
        transferId: t.id,
        attemptId: t.attemptId!,
        totalBytes: 65536,
      ).expand((chunk) => chunk).toList();
      expect(Uint8List.fromList(decrypted), plain);
      expect(rig.serverErrors, isEmpty);
    },
  );

  test('a missing or unparsable header is a 400 and burns nothing', () async {
    final rig = await TransferRig.create();
    final t = await rig.offerVoice();
    for (final overrides in <Map<String, String?>>[
      {'x-transfer-attempt': null},
      {'x-file-size': null},
      {'x-file-size': 'big'},
      {'x-file-size': '65536.5'},
    ]) {
      final res = await rig.get(t.id, rig.headers(t, overrides: overrides));
      expect(res.status, 400, reason: '$overrides');
    }
    // 토큰이 안 타서 정상 요청은 여전히 통과함
    expect((await rig.get(t.id, rig.headers(t))).status, 200);
  });

  test(
    'a wrong token, attempt or size is a 403 and consumes nothing',
    () async {
      final rig = await TransferRig.create();
      final t = await rig.offerVoice();
      for (final overrides in <Map<String, String?>>[
        {'x-transfer-token': 'not-the-token'},
        {'x-transfer-token': ''},
        {'x-transfer-attempt': 'stale-attempt'},
        {'x-file-size': '65535'},
        {'x-file-size': '65537'},
      ]) {
        final res = await rig.get(t.id, rig.headers(t, overrides: overrides));
        expect(res.status, 403, reason: '$overrides');
      }
      expect((await rig.get(t.id, rig.headers(t))).status, 200);
    },
  );

  test('a token is single use — a duplicate GET is refused', () async {
    final rig = await TransferRig.create();
    final t = await rig.offerVoice();
    final headers = rig.headers(t);

    // 첫 GET의 응답 헤더만 받고 body는 아직 안 읽은 채로 두 번째 GET
    final first = await rig.client.getUrl(
      Uri.parse(
        'http://${rig.bound.host}:${rig.bound.port}/api/download/${t.id}',
      ),
    );
    headers.forEach(first.headers.set);
    final firstResponse = await first.close();
    expect(firstResponse.statusCode, 200);
    expect((await rig.get(t.id, headers)).status, 403, reason: 'mid-flight');

    await firstResponse.drain<void>();
    await pumpEventQueue(times: 30);
    expect((await rig.get(t.id, headers)).status, 403, reason: 'after EOF');
  });

  test('wire EOF alone never completes — the matching ACK does', () async {
    final rig = await TransferRig.create();
    final t = await rig.offerVoice();
    await rig.get(t.id, rig.headers(t));
    await pumpEventQueue(times: 30);

    var now = rig.store.transfer(t.id)!;
    expect(now.state, TransferState.transferring);
    expect(now.transferredBytes, 65536);

    await rig.remote.sendFileReceived(t.id, attemptId: t.attemptId!);
    await pumpEventQueue(times: 60);
    now = rig.store.transfer(t.id)!;
    expect(now.state, TransferState.complete);
  });
}
