part of '../component_themes.dart';

// 데스크톱 OS 관례에 맞춘 모서리와 눌림 표시. Windows(Fluent 2)는 컨트롤 4·메뉴와 창 8, Linux(libadwaita)는
// 버튼과 입력 6·메뉴와 카드와 창 12이고, 둘 다 물결(리플) 없이 색만 바뀜. 그 밖의 OS는 앱 기본 모서리
// (Apple은 대화상자·스위치가 이미 Cupertino로 바뀜)
typedef _Shape = ({
  double control,
  double small,
  double overlay,
  double surface,
  double sheet,
  bool ripple,
});

_Shape _shapeFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => (
    control: 4,
    small: 4,
    overlay: 8,
    surface: 8,
    sheet: 8,
    ripple: false,
  ),
  TargetPlatform.linux => (
    control: 6,
    small: 6,
    overlay: 12,
    surface: 12,
    sheet: 12,
    ripple: false,
  ),
  _ => (
    control: AppRadius.md,
    small: AppRadius.sm,
    overlay: AppRadius.md,
    surface: AppRadius.lg,
    sheet: AppRadius.xl,
    ripple: true,
  ),
};
