import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'package:intragram/core/display_regions.dart';
import 'package:intragram/core/os_privacy.dart';

// 접힘선 양쪽이 이보다 좁으면 둘로 안 나눔 (접힘선에 걸친 작은 자유형 창 등)
const kMinPaneWidth = 300.0;

// 짧은 변이 이 이상인 iPhone(phone idiom)은 펼친 내부 화면으로 봄. 일반 iPhone은 눕혀도 440pt 안팎
const kUnfoldedPhoneSide = 620.0;

// 화면을 위아래로 가로질러 좌우로 가르는 힌지·접힘선. 평평하게 편(postureFlat) 폭 0 접힘선도 경계로 씀
DisplayFeature? verticalHinge(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  for (final feature in MediaQuery.displayFeaturesOf(context)) {
    final bounds = feature.bounds;
    if ((feature.type == DisplayFeatureType.hinge ||
            feature.type == DisplayFeatureType.fold) &&
        bounds.top <= 0 &&
        bounds.bottom >= size.height &&
        bounds.left >= kMinPaneWidth &&
        size.width - bounds.right >= kMinPaneWidth) {
      return feature;
    }
  }
  return null;
}

// iOS 27.1 전의 펼친 iPhone은 접힘선을 알려 주지 않음: 세로로 편 내부 화면이면 가운데를 접힘선으로 봄.
// 27.1+는 OS가 알려 준 접힘선이 MediaQuery.displayFeatures로 들어와 verticalHinge가 씀
// (둘 다 첫 화면 전에 물어 둔 값. cachedIsPad가 iPad거나 모르면(null) 안 나눔)
Rect? phoneCrease(Size size) {
  if (defaultTargetPlatform != TargetPlatform.iOS ||
      DisplayRegions.features.value != null ||
      OsPrivacy.cachedIsPad != false ||
      size.shortestSide < kUnfoldedPhoneSide ||
      size.width >= size.height) {
    return null;
  }
  return Rect.fromLTWH(size.width / 2, 0, 0, size.height);
}

DisplayFeature? tabletopFold(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  for (final feature in MediaQuery.displayFeaturesOf(context)) {
    final bounds = feature.bounds;
    if ((feature.type == DisplayFeatureType.hinge ||
            feature.type == DisplayFeatureType.fold) &&
        feature.state == DisplayFeatureState.postureHalfOpened &&
        bounds.left <= 0 &&
        bounds.right >= size.width &&
        bounds.top > 0 &&
        bounds.bottom < size.height) {
      return feature;
    }
  }
  return null;
}
