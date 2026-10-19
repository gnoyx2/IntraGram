import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/transfer_tile.dart';
import 'package:intragram/l10n/strings.dart';

// 크기·시각 표기가 기기 파일 앱과 OS 시계 설정을 그대로 따르는지 고정
void main() {
  test('file sizes use decimal units like the phone file apps', () {
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1.0 KB');
    expect(formatBytes(48 * 1024), '49.2 KB');
    expect(formatBytes(150000), '150 KB');
    expect(formatBytes(999499), '999 KB');
    // 반올림 경계는 다음 단위로 넘어감
    expect(formatBytes(999500), '1.0 MB');
    expect(formatBytes(4 * 1000 * 1000 * 1000), '4.0 GB');
  });

  test('the clock follows the 24-hour setting and the app language', () {
    const en = S(AppLang.en);
    const ko = S(AppLang.ko);
    final afternoon = DateTime(2026, 10, 9, 15, 5);
    final midnight = DateTime(2026, 10, 9, 0, 7);
    final noon = DateTime(2026, 10, 9, 12, 0);

    expect(en.clock(afternoon, use24h: true), '15:05');
    expect(ko.clock(midnight, use24h: true), '00:07');
    expect(en.clock(afternoon, use24h: false), '3:05 PM');
    expect(en.clock(midnight, use24h: false), '12:07 AM');
    expect(en.clock(noon, use24h: false), '12:00 PM');
    expect(ko.clock(afternoon, use24h: false), '오후 3:05');
    expect(ko.clock(midnight, use24h: false), '오전 12:07');
  });
}
