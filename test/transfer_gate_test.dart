import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/registry/transfer_gate.dart';

void main() {
  test('lets up to maxConcurrent through immediately', () async {
    final gate = TransferConcurrencyGate(maxConcurrent: 2);
    var acquired = 0;
    await gate.acquire();
    acquired++;
    await gate.acquire();
    acquired++;
    expect(acquired, 2);
  });

  test('queues past the cap and releases in order', () async {
    final gate = TransferConcurrencyGate(maxConcurrent: 1);
    await gate.acquire();

    var secondAcquired = false;
    final pending = gate.acquire().then((_) => secondAcquired = true);

    // 아직 첫 번째가 안 놓아줌: 두 번째는 대기 중이어야 함
    await Future<void>.delayed(Duration.zero);
    expect(secondAcquired, isFalse);

    gate.release();
    await pending;
    expect(secondAcquired, isTrue);
  });

  test(
    'a released slot with no waiters lets the next acquire through',
    () async {
      final gate = TransferConcurrencyGate(maxConcurrent: 1);
      await gate.acquire();
      gate.release();
      var acquiredAgain = false;
      await gate.acquire().then((_) => acquiredAgain = true);
      expect(acquiredAgain, isTrue);
    },
  );
}
