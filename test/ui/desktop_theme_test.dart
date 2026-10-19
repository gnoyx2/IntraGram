import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';

// 데스크톱 OS 관례: Windows는 Fluent(컨트롤 4·창 8), Linux는 libadwaita(6·12, 제목이 가운데인 헤더바),
// 둘 다 물결 효과 없음. 다른 OS는 원래 모서리 그대로
void main() {
  double radius(ShapeBorder? shape) =>
      ((shape! as RoundedRectangleBorder).borderRadius as BorderRadius)
          .topLeft
          .x;
  double buttonRadius(ButtonStyle? style) =>
      radius(style!.shape!.resolve(<WidgetState>{}));

  ThemeData themeOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return AppTheme.light();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  test('Windows follows Fluent corners without ripples', () {
    final t = themeOn(TargetPlatform.windows);
    expect(buttonRadius(t.filledButtonTheme.style), 4);
    expect(buttonRadius(t.textButtonTheme.style), 4);
    expect(radius(t.popupMenuTheme.shape), 8);
    expect(radius(t.dialogTheme.shape), 8);
    expect(t.splashFactory, same(NoSplash.splashFactory));
    expect(t.appBarTheme.centerTitle, isFalse);
  });

  test('Linux follows libadwaita with a centred header bar', () {
    final t = themeOn(TargetPlatform.linux);
    expect(buttonRadius(t.filledButtonTheme.style), 6);
    expect(radius(t.cardTheme.shape), 12);
    expect(radius(t.dialogTheme.shape), 12);
    expect(t.splashFactory, same(NoSplash.splashFactory));
    expect(t.appBarTheme.centerTitle, isTrue);
    expect(t.appBarTheme.scrolledUnderElevation, 0);
    expect(t.appBarTheme.shape, isA<Border>());
  });

  test('other platforms keep the app corners and ripples', () {
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      final t = themeOn(p);
      expect(buttonRadius(t.filledButtonTheme.style), AppRadius.md);
      expect(radius(t.dialogTheme.shape), AppRadius.lg, reason: '$p');
      expect(t.splashFactory, isNot(same(NoSplash.splashFactory)));
      expect(t.appBarTheme.centerTitle, isFalse);
    }
  });
}
