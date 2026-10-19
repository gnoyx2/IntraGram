import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/secure_bytes.dart';

void main() {
  test('alloc gives a zeroed buffer of the requested length', () {
    final b = SecureBytes.alloc(8);
    expect(b.length, 8);
    expect(b.bytes, everyElement(0));
    expect(b.isDestroyed, isFalse);
  });

  test('copy duplicates the source and is independent of it', () {
    final source = <int>[1, 2, 3, 4];
    final b = SecureBytes.copy(source);
    source[0] = 99;
    expect(b.bytes, [1, 2, 3, 4]);
  });

  test('destroy scrubs the buffer and blocks further use', () {
    final b = SecureBytes(Uint8List.fromList([9, 9, 9, 9]));
    b.destroy();
    expect(b.isDestroyed, isTrue);
    expect(() => b.bytes, throwsStateError);
    b.destroy(); // 멱등
  });

  test('wipe overwrites a modifiable list to all-zero', () {
    final data = Uint8List.fromList(List<int>.filled(32, 0xAB));
    SecureBytes.wipe(data);
    expect(data, everyElement(0));
  });

  test('wipe is a no-op (not a throw) on an unmodifiable list', () {
    final frozen = List<int>.unmodifiable([1, 2, 3]);
    expect(() => SecureBytes.wipe(frozen), returnsNormally);
    expect(frozen, [1, 2, 3]);
  });

  test('wipe tolerates an empty list', () {
    expect(() => SecureBytes.wipe(<int>[]), returnsNormally);
  });
}
