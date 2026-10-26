import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:intragram/theme/adaptive_layout.dart';

// 이 폭부터 목록 옆에 대화를 띄움 (Material 확장 창 기준, iPad 가로·데스크톱 창)
const kTwoPaneMinWidth = 840.0;
const kListPaneWidth = 360.0;

// 2단 배치: 목록 폭과 대화 창이 시작하는 x (1단이면 null). 세로 힌지·접힘선이나 펼친 iPhone의 가운데가
// 있으면 그 경계에 맞추고, 없으면 kTwoPaneMinWidth부터 목록을 kListPaneWidth로 둠
({double list, double chat})? paneSplit(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final crease = verticalHinge(context)?.bounds ?? phoneCrease(size);
  if (crease != null) {
    // 폭 없는 접힘선은 대화 창 앞에 1pt 구분선을 둠
    return (
      list: crease.left,
      chat: crease.width == 0 ? crease.left + 1 : crease.right,
    );
  }
  if (size.width < kTwoPaneMinWidth) return null;
  return (list: kListPaneWidth, chat: kListPaneWidth + 1);
}

// 목록과 대화 창을 늘 같은 자리(Stack)에 두고 배치만 바꿈: 접고 펼쳐도 두 창의 상태(입력 중인 글·스크롤)가 남음.
// 좁은 창에선 대화 창이 목록 위를 덮고(iOS 스와이프 뒤로 때 밑의 목록이 보임), 열린 대화가 없으면 목록만 쓰임
class AdaptivePanes extends StatelessWidget {
  const AdaptivePanes({
    required this.split,
    required this.chatOpen,
    required this.chatSettled,
    required this.list,
    required this.pane,
    super.key,
  });

  final ({double list, double chat})? split;
  final bool chatOpen;
  // 대화가 다 들어와 멈췄는지 (ChatPane.onSettled)
  final ValueListenable<bool> chatSettled;
  final Widget list;
  final Widget pane;

  @override
  Widget build(BuildContext context) {
    final split = this.split;
    final width = split?.list ?? MediaQuery.sizeOf(context).width;
    final left = split?.chat ?? 0;
    final gap = split == null ? 0.0 : left - width;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: width,
          child: _Covered(
            covered: split == null && chatOpen,
            // 덮은 대화가 멈춰 있는 동안은 목록을 그리지도 않음 (전환·뒤로 제스처 땐 다시 그림)
            child: ValueListenableBuilder<bool>(
              valueListenable: chatSettled,
              builder: (context, settled, list) {
                final hidden = split == null && chatOpen && settled;
                return Offstage(
                  offstage: hidden,
                  child: TickerMode(enabled: !hidden, child: list!),
                );
              },
              child: PaneMedia(removeRight: split != null, child: list),
            ),
          ),
        ),
        // 접힘선 자리: 폭 없는 접힘선은 1pt 구분선, 폭이 있으면(힌지·OS가 알려 준 접힘선 여백) 바탕을 칠하고
        // 가운데 구분선 (안 칠하면 창 바탕색이 비침)
        Positioned(
          left: width,
          top: 0,
          bottom: 0,
          width: gap,
          child: gap > 0
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: const Center(
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          right: 0,
          child: _Covered(
            covered: split == null && !chatOpen,
            // 창 안 경로의 모달 장벽(BlockSemantics)이 옆 목록까지 스크린 리더에서 지우지 않게 경계를 둠
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: PaneMedia(
                left: left,
                removeLeft: split != null,
                child: pane,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 덮였거나 비어서 안 쓰는 창: 손·키보드 초점·스크린 리더에서 빼되 그림은 그대로 둠
// (애니메이션은 안 멈춤: 빈 대화 창에서도 닫히는 대화의 전환은 끝까지 돌아야 함)
class _Covered extends StatelessWidget {
  const _Covered({required this.covered, required this.child});

  final bool covered;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: covered,
    child: ExcludeFocus(
      excluding: covered,
      child: ExcludeSemantics(excluding: covered, child: child),
    ),
  );
}

// 이 창 크기를 MediaQuery로 내려 줌: 말풍선 최대 폭·좁은 폭 판단이 창 전체가 아니라 이 창을 봄
// 안쪽 가장자리의 안전 영역 여백은 뺌
class PaneMedia extends StatelessWidget {
  const PaneMedia({
    required this.child,
    this.removeLeft = false,
    this.removeRight = false,
    this.left = 0,
    super.key,
  });

  final Widget child;
  final bool removeLeft;
  final bool removeRight;
  final double left;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final bounds = Rect.fromLTWH(
        left,
        0,
        constraints.maxWidth,
        constraints.maxHeight,
      );
      final media = MediaQuery.of(context).removeDisplayFeatures(bounds);
      return MediaQuery(
        data: media
            .removePadding(removeLeft: removeLeft, removeRight: removeRight)
            .copyWith(
              size: constraints.biggest,
              displayFeatures: [
                for (final feature in media.displayFeatures)
                  DisplayFeature(
                    bounds: feature.bounds
                        .intersect(bounds)
                        .shift(Offset(-left, 0)),
                    type: feature.type,
                    state: feature.state,
                  ),
              ],
            ),
        child: child,
      );
    },
  );
}
