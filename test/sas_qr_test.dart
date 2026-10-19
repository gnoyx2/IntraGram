import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/sas_qr.dart';

void main() {
  test('encodeSasQr wraps the digits with the scheme prefix', () {
    expect(encodeSasQr('314159'), 'intragram-sas:314159');
  });

  group('sasScanVerdict', () {
    test('true only when the prefix and all six digits agree', () {
      expect(sasScanVerdict('intragram-sas:314159', '314159'), isTrue);
      expect(sasScanVerdict('  intragram-sas:314159  ', '314159'), isTrue);
    });

    // 다른 숫자의 SAS 코드는 무시하지 않고 불일치로 알림 (중간자가 있으면 바로 이 경우)
    test('false on a security code with other digits', () {
      expect(sasScanVerdict('intragram-sas:999999', '314159'), isFalse);
      expect(sasScanVerdict('intragram-sas:', '314159'), isFalse);
    });

    test('null on anything that is not a security code', () {
      expect(sasScanVerdict('314159', '314159'), isNull);
      expect(sasScanVerdict('https://192.168.1.9:7890', '314159'), isNull);
      expect(sasScanVerdict('', '314159'), isNull);
    });
  });
}
