// 4pt 간격 스케일. 새 여백이 필요하면 여기 추가하고 화면 코드에 매직 넘버를 두지 않음
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;
}

// 모서리 반경 스케일. 값 하나가 앱 톤을 정하므로 컴포넌트별로 숫자를 따로 두지 않음
class AppRadius {
  const AppRadius._();

  static const double tail = 6;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

// 반 픽셀 경계로 서피스 깊이를 구분함
class AppBorder {
  const AppBorder._();

  static const double hairline = 0.5;
}

// 말풍선 위 보조 글씨(시각·크기·전송 상태)의 본문색 불투명도
// 그라디언트의 밝은 끝에서도 7:1(AAA) 이상 유지함
class AppOpacity {
  const AppOpacity._();

  static const double secondaryText = 0.85;
}
