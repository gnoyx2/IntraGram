import 'package:flutter/material.dart';

import 'color_schemes.dart';
import 'component_themes.dart';

export 'color_schemes.dart';

class AppTheme {
  const AppTheme._();

  // 대비 증가(iOS 접근성 설정, MediaQuery.highContrast): 경계선과 보조 글씨를 본문 쪽으로 끌어올림
  static ColorScheme _highContrast(ColorScheme scheme) => scheme.copyWith(
    outlineVariant: scheme.outline,
    onSurfaceVariant: scheme.onSurface,
  );

  static ThemeData light({
    bool highContrast = false,
    bool reduceTransparency = false,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.accentLight,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppPalette.accentLight,
          onPrimary: const Color(0xFFFFFFFF),
          primaryContainer: const Color(0xFFE8F0FF),
          onPrimaryContainer: const Color(0xFF1E40AF),
          tertiary: const Color(0xFF065F46),
          error: const Color(0xFF991B1B),
          // 눈부심 없는 오프화이트·소프트 징크 단계
          surface: AppPalette.scaffoldLight,
          surfaceContainerLowest: AppPalette.scaffoldLight,
          surfaceContainerLow: const Color(0xFFF6F8FA),
          surfaceContainer: const Color(0xFFEEF2F6),
          surfaceContainerHigh: const Color(0xFFE9EEF4),
          surfaceContainerHighest: const Color(0xFFE5EBF2),
          onSurface: const Color(0xFF171C26),
          onSurfaceVariant: const Color(0xFF3D495C),
          outlineVariant: const Color(0xFFD6DEE8),
        );
    return _build(scheme, ChatColors.light, highContrast || reduceTransparency);
  }

  static ThemeData dark({
    bool highContrast = false,
    bool reduceTransparency = false,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.accentDark,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppPalette.accentDark,
          onPrimary: const Color(0xFF0A1633),
          primaryContainer: const Color(0xFF182D4D),
          onPrimaryContainer: const Color(0xFFBFDBFE),
          tertiary: const Color(0xFF6EE7B7),
          error: const Color(0xFFFFB4AB),
          // 무채색 대신 푸른 기가 도는 옵시디언·딥 슬레이트 단계
          surface: AppPalette.scaffoldDark,
          surfaceContainerLowest: AppPalette.chatCanvasDark,
          surfaceContainerLow: const Color(0xFF10141B),
          surfaceContainer: const Color(0xFF141820),
          surfaceContainerHigh: const Color(0xFF191D27),
          surfaceContainerHighest: const Color(0xFF1D222E),
          onSurface: const Color(0xFFF1F5FC),
          onSurfaceVariant: const Color(0xFFB6C2D2),
          outlineVariant: const Color(0xFF282E3D),
        );
    return _build(scheme, ChatColors.dark, highContrast || reduceTransparency);
  }

  static ThemeData _build(ColorScheme scheme, ChatColors chat, bool defined) =>
      buildComponentThemes(
        defined ? _highContrast(scheme) : scheme,
        definedBorders: defined,
      ).copyWith(
        extensions: <ThemeExtension<dynamic>>[
          defined
              ? chat.copyWith(
                  bubbleMineEdge: scheme.outline,
                  bubbleShadow: Colors.transparent,
                )
              : chat,
        ],
      );
}
