import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/file_transfer_crypto_pair.dart';

void main() {
  group('encryptedFileLength', () {
    test('zero bytes is zero', () {
      expect(encryptedFileLength(0), 0);
    });

    Future<void> expectMatchesRealWireLength(int plaintextSize) async {
      final (a, _) = await pairSessions();
      final plain = Uint8List.fromList(
        List<int>.generate(plaintextSize, (i) => i & 0xff),
      );
      final wireLength = await encryptForTest(a, plain).then((w) => w.length);
      expect(encryptedFileLength(plaintextSize), wireLength);
    }

    test(
      'matches the real encrypted stream length for a small payload',
      () => expectMatchesRealWireLength(100),
    );

    test(
      'matches the real encrypted stream length for exactly one chunk',
      () => expectMatchesRealWireLength(kFileChunkBytes),
    );

    test(
      'matches the real encrypted stream length for one chunk plus '
      'remainder',
      () => expectMatchesRealWireLength(kFileChunkBytes + 777),
    );

    test(
      'matches the real encrypted stream length for exactly two chunks',
      () => expectMatchesRealWireLength(kFileChunkBytes * 2),
    );
  });
}
