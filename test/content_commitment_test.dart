import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/audit/content_commitment.dart';

void main() {
  const abcSha256 = 'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=';

  test('Dart SHA-256 and streamed chunks match the abc known vector', () async {
    final body = utf8.encode('abc');
    expect(sha256B64(body), abcSha256);
    String? digest;
    final source = Stream<Uint8List>.fromIterable([
      Uint8List.fromList(body.take(1).toList()),
      Uint8List.fromList(body.skip(1).toList()),
    ]);
    final received = await sha256Tap(
      source,
      (value) => digest = value,
    ).expand((chunk) => chunk).toList();
    expect(received, body);
    expect(digest, abcSha256);
  });

  test(
    'a failed stream never commits its successfully delivered prefix',
    () async {
      final source = StreamController<List<int>>();
      String? digest;
      final errors = <Object>[];
      final done = Completer<void>();
      sha256Tap(
        source.stream,
        (value) => digest = value,
      ).listen((_) {}, onError: errors.add, onDone: done.complete);
      source
        ..add([1, 2, 3])
        ..addError(StateError('read failed'));
      await source.close();
      await done.future;
      expect(errors, hasLength(1));
      expect(digest, isNull);
    },
  );

  test('cancelling a reader never commits its prefix', () async {
    final source = StreamController<List<int>>();
    String? digest;
    final reader = sha256Tap(
      source.stream,
      (value) => digest = value,
    ).listen((_) {});
    source.add([1, 2, 3]);
    await pumpEventQueue();
    await reader.cancel();
    await source.close();
    expect(digest, isNull);
  });
}
