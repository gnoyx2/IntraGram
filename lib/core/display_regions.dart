import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;

// iOS 27.1+가 알려 주는 접는 iPhone의 접힘선(UIView.ReservedRegion .division, ios/Runner/DisplayRegions.swift).
// Flutter iOS 엔진은 MediaQuery.displayFeatures를 안 채워서 앱 루트가 이걸 넣음 (app_accessibility.dart).
// null이면 OS가 안 알려 줌(27.1 전 iOS·다른 OS): 펼친 iPhone은 화면 크기로 짐작함 (phoneCrease)
abstract final class DisplayRegions {
  static final features = ValueNotifier<List<DisplayFeature>?>(null);

  static void update(Object? message) => features.value = parse(message);

  // {status: UIHinge.Status(0 모름·1 닫힘·2 반쯤 엶·3 다 엶), regions: [[x, y, 폭, 높이, 활성 1·0], ...]}
  // 좌표는 창 기준 포인트(= 논리 픽셀). 모양이 틀리면 OS가 안 알려 준 것으로 봄
  @visibleForTesting
  static List<DisplayFeature>? parse(Object? message) {
    if (message is! Map) return null;
    final status = message['status'];
    final regions = message['regions'];
    if (status is! int || regions is! List) return null;
    return [
      for (final region in regions)
        if (region
            case [
              final num x,
              final num y,
              final num width,
              final num height,
              final num active,
            ]
            when [x, y, width, height].every((v) => v.isFinite) &&
                width >= 0 &&
                height >= 0)
          DisplayFeature(
            bounds: Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              width.toDouble(),
              height.toDouble(),
            ),
            // 화면이 이어진 접는 패널이라 가리지 않는 fold. 비활성(평평하게 폄)은 Android 평평한 폴드처럼 다룸
            type: DisplayFeatureType.fold,
            state: active == 0 || status == 3
                ? DisplayFeatureState.postureFlat
                : status == 2
                ? DisplayFeatureState.postureHalfOpened
                : DisplayFeatureState.unknown,
          ),
    ];
  }
}
