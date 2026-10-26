part of '../component_themes.dart';

// headerBar(Linux): GNOME 헤더바처럼 제목을 가운데 두고, 스크롤해도 그림자 대신 아래 실선 하나
AppBarTheme _appBarTheme(
  ColorScheme scheme, {
  bool headerBar = false,
  bool definedBorders = false,
}) => AppBarTheme(
  backgroundColor: scheme.surface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: headerBar ? 0 : 1,
  centerTitle: headerBar,
  shape: headerBar || definedBorders
      ? Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: definedBorders ? AppBorder.defined : AppBorder.hairline,
          ),
        )
      : null,
  titleTextStyle: AppType.scale.titleMedium?.copyWith(color: scheme.onSurface),
  toolbarTextStyle: AppType.scale.bodyMedium?.copyWith(color: scheme.onSurface),
  // 명시하지 않으면 AppBar가 전경색을 스스로 계산해서 iOS에서 아이콘이 흰색으로 뜬 적 있음
  foregroundColor: scheme.onSurface,
  iconTheme: IconThemeData(color: scheme.onSurface),
  actionsIconTheme: IconThemeData(color: scheme.onSurface),
  // 상태바·내비바 아이콘 밝기를 테마로 정함 (SystemChrome을 직접 안 불러도 됨)
  systemOverlayStyle:
      (scheme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(systemNavigationBarColor: Colors.transparent),
);

// iOS는 스와이프 뒤로 가기, Android는 predictive back, 데스크톱(macOS 포함)은 페이드를 씀 (Mac 창에서 옆으로 밀려 들어오는 건 Mac 관례가 아님)
PageTransitionsTheme _pageTransitionsTheme() => PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
  },
);
