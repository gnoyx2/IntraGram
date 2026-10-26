import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

import 'package:intragram/theme/adaptive_layout.dart';

// 테이블탑에선 시트가 위아래 두 화면에 걸침(QR은 위, 조작은 아래). 세로 힌지는 여전히 피함
class PortalSheetRoute extends ModalBottomSheetRoute<void> {
  PortalSheetRoute({
    required Widget child,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.modalBarrierColor,
  }) : super(
         isScrollControlled: true,
         showDragHandle: true,
         builder: (context) {
           final fold = (ModalRoute.of(context)! as PortalSheetRoute)._fold;
           if (fold == null) return child;
           return MediaQuery(
             data: MediaQuery.of(context).copyWith(
               displayFeatures: [
                 ...MediaQuery.displayFeaturesOf(context),
                 fold,
               ],
             ),
             child: child,
           );
         },
       );

  DisplayFeature? _fold;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    _fold = tabletopFold(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        displayFeatures: MediaQuery.displayFeaturesOf(
          context,
        ).where((feature) => feature != _fold).toList(),
      ),
      child: Builder(
        builder: (context) =>
            super.buildPage(context, animation, secondaryAnimation),
      ),
    );
  }
}
