import 'package:flutter/material.dart';

// OS '동작 줄이기'가 켜지면 Duration.zero: 애니메이션 길이는 다 이걸 거침
Duration motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

// 말풍선·칩·버튼이 같은 박자로 반응하도록 기본 모션을 한곳에 둠
class AppMotion {
  const AppMotion._();

  static const press = Duration(milliseconds: 140);
  static const settle = Duration(milliseconds: 240);
  static const pop = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const pressedScale = 0.97;
}

// 주요 목록용: 내용이 짧아도 iOS는 튕기고 Android는 늘어남 (물리는 플랫폼 기본)
const ScrollPhysics listPhysics = AlwaysScrollableScrollPhysics();
