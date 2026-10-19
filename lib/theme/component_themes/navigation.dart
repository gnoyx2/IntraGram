part of '../component_themes.dart';

// headerBar(Linux): GNOME 헤더바처럼 제목을 가운데 두고, 스크롤해도 그림자 대신 아래 실선 하나
AppBarTheme _appBarTheme(
  ColorScheme scheme, {
  bool headerBar = false,
}) => AppBarTheme(
  backgroundColor: scheme.surface,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: headerBar ? 0 : 1,
  centerTitle: headerBar,
  shape: headerBar
      ? Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: AppBorder.hairline,
          ),
        )
      : null,
  titleTextStyle: AppType.scale.titleMedium?.copyWith(color: scheme.onSurface),
  toolbarTextStyle: AppType.scale.bodyMedium?.copyWith(color: scheme.onSurface),
  // 명시 안 하면 AppBar가 전경색을 스스로 계산해서 iOS에서 타이머/더보기 아이콘이 흰색으로 뜨는
  // 보고가 있었음. 플랫폼별 기본 계산에 기대지 않게 못 박음
  foregroundColor: scheme.onSurface,
  iconTheme: IconThemeData(color: scheme.onSurface),
  actionsIconTheme: IconThemeData(color: scheme.onSurface),
  // 상태바/내비게이션바 아이콘 밝기를 테마에 맞춰 선언적으로 바꿈 (SystemChrome 명령형 호출 불필요)
  systemOverlayStyle:
      (scheme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(systemNavigationBarColor: Colors.transparent),
);

// iOS는 스와이프-백 Cupertino 전환, Android는 predictive back, 데스크톱(macOS 포함)은 페이드
// macOS 창 안에서 옆으로 밀려 들어오고 왼쪽 끝을 끌면 뒤로 가는 건 Mac 앱 관례가 아님
// (라우트마다 안 건드리고 여기 한 곳에서 지정)
PageTransitionsTheme _pageTransitionsTheme() => PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
  },
);
