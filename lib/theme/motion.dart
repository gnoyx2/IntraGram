import 'package:flutter/material.dart';

// OS "동작 줄이기" 설정이 켜지면 Duration.zero. 전정 감각 민감 사용자/스크린 리더 사용자가
// 튕김/리플/오버슈트 대신 즉시 전환을 받도록 모든 애니메이션 duration을 이 함수로 통과시킴
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

// 주요 목록용. 내용이 짧아도 iOS는 튕기고 Android는 스트레치가 걸림
// 물리 자체는 플랫폼 기본(iOS 바운스, Android 클램핑 + 스트레치)을 그대로 따라감
const ScrollPhysics listPhysics = AlwaysScrollableScrollPhysics();
