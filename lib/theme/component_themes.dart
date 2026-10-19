import 'package:flutter/cupertino.dart'
    show CupertinoPageTransitionsBuilder, CupertinoThemeData;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'tokens.dart';
import 'type_scale.dart';

part 'component_themes/navigation.dart';
part 'component_themes/buttons.dart';
part 'component_themes/desktop_shape.dart';

// platform은 테스트용 (앱은 실행 중인 OS)
ThemeData buildComponentThemes(ColorScheme scheme, {TargetPlatform? platform}) {
  final os = platform ?? defaultTargetPlatform;
  final shape = _shapeFor(os);
  final radiusMd = BorderRadius.circular(shape.control);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: AppType.scale.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: _appBarTheme(scheme, headerBar: os == TargetPlatform.linux),
    splashFactory: shape.ripple ? null : NoSplash.splashFactory,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // iOS·macOS 적응형 대화상자 버튼 글씨: 반투명 회색 바탕 위에서 기본 파랑은 3.5:1이라 더 진하게
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: scheme.brightness == Brightness.light
          ? scheme.onPrimaryContainer
          : scheme.primary,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardTheme: CardThemeData(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.surface),
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppBorder.hairline,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _filledButtonStyle(scheme, shape.control),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _textButtonStyle(scheme, shape.small),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _textButtonStyle(scheme, shape.small).copyWith(
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant, width: AppBorder.hairline),
        ),
      ),
    ),
    // 앱 전체 48dp 탭 타깃 하한선
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape.ripple
            ? const StadiumBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(shape.control),
              ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      // 입력창 경계는 비텍스트 대비 3:1이 필요해서 outline (outlineVariant는 1.4:1)
      border: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(
          color: scheme.outline,
          width: AppBorder.hairline,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(
          color: scheme.outline,
          width: AppBorder.hairline,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      hintStyle: AppType.scale.bodyLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.surface),
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppBorder.hairline,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.huge,
      ),
      titleTextStyle: AppType.scale.titleMedium?.copyWith(
        color: scheme.onSurface,
      ),
      contentTextStyle: AppType.scale.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shape.sheet)),
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppBorder.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      minVerticalPadding: AppSpacing.sm,
      titleTextStyle: AppType.scale.titleSmall?.copyWith(
        color: scheme.onSurface,
      ),
      subtitleTextStyle: AppType.scale.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: AppType.scale.labelMedium,
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.brightness == Brightness.light
          ? scheme.onPrimaryContainer
          : scheme.primary,
      textColor: scheme.onPrimary,
      textStyle: AppType.scale.labelSmall,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: AppBorder.hairline,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(shape.small),
      ),
      textStyle: AppType.scale.labelSmall?.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    // 자동으로 붙는 데스크톱 스크롤바(MaterialScrollBehavior)는
    // 스타일링만 함 (Scrollbar를 따로 감쌀 필요 없음)
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? 6 : 4,
      ),
      radius: Radius.circular(AppRadius.pill),
      crossAxisMargin: AppSpacing.xxs,
      mainAxisMargin: AppSpacing.xs,
      interactive: true,
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => scheme.onSurfaceVariant.withValues(
          alpha: states.contains(WidgetState.dragged)
              ? 0.8
              : states.contains(WidgetState.hovered)
              ? 0.7
              : 0.6, // 가만히 있을 때도 3:1
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shape.overlay),
        side: BorderSide(
          color: scheme.outlineVariant,
          width: AppBorder.hairline,
        ),
      ),
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      color: scheme.surface,
      // 색 없는 TextStyle이면 항목 글씨가 렌더 시점의 ambient DefaultTextStyle에 기대서
      // 타이머/더보기 메뉴 글씨가 안 보이는 문제가 있었음. 명시해서 그 의존을 없앰
      labelTextStyle: WidgetStatePropertyAll(
        AppType.scale.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    pageTransitionsTheme: _pageTransitionsTheme(),
  );
}
