import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/sas_generator.dart';

// digitsFromBytes의 내부 거부 임계값과 같은 공식: % 1000000으로 감쌀
// 값이 이 문턱 이상이면 레인이 버려짐 (구현부 _kRejectThreshold와 동일)
const int _threshold = (0x100000000 ~/ 1000000) * 1000000; // 4,294,000,000

List<int> _lane(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

String _pad(int value) => (value % 1000000).toString().padLeft(6, '0');

void main() {
  group('digitsFromBytes', () {
    test('accepts a lane just under the reject threshold', () {
      expect(digitsFromBytes(_lane(_threshold - 1)), _pad(_threshold - 1));
    });

    test('zero-pads to 6 digits', () {
      expect(digitsFromBytes(_lane(0)), '000000');
      expect(digitsFromBytes(_lane(999999)), '999999');
    });

    test(
      'a lane at/above the threshold is skipped in favor of the next lane',
      () {
        final bytes = [..._lane(_threshold), ..._lane(42)];
        expect(digitsFromBytes(bytes), '000042');
      },
    );

    test('skips multiple consecutive out-of-range lanes', () {
      final bytes = [
        ..._lane(_threshold),
        ..._lane(0xFFFFFFFF),
        ..._lane(999999),
      ];
      expect(digitsFromBytes(bytes), '999999');
    });

    test('throws rather than silently return a biased digit', () {
      final bytes = [..._lane(_threshold), ..._lane(0xFFFFFFFF)];
      expect(() => digitsFromBytes(bytes), throwsStateError);
    });
  });
}
