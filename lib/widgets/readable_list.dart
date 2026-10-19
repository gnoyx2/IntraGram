import 'dart:math' as math;

import 'package:flutter/material.dart';

// 넓은 창에서 글 줄이 너무 길어지지 않게 하는 열 폭 (설정·검색·홈 목록)
const kReadableWidth = 720.0;

// 대화 열(말풍선·입력창) 최대 폭
const kChatColumnWidth = 840.0;

// 가운데 열을 만드는 좌우 여백
double readableSide(double width, [double maxWidth = kReadableWidth]) =>
    math.max(0, (width - maxWidth) / 2);

// 내용만 가운데 열로 모으는 목록. 스크롤 영역(휠·스크롤바)은 창 전폭 그대로 둠
// padding을 직접 주면 ListView가 안전 영역을 안 넣어서 여기서 같이 더함
class ReadableList extends StatelessWidget {
  const ReadableList({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.physics,
    super.key,
  });

  final List<Widget> children;

  // 열 안쪽에 더할 여백
  final EdgeInsets padding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = readableSide(box.maxWidth);
      final safe = MediaQuery.paddingOf(context);
      return ListView(
        physics: physics,
        padding:
            EdgeInsets.fromLTRB(
              math.max(side, safe.left),
              safe.top,
              math.max(side, safe.right),
              safe.bottom,
            ) +
            padding,
        children: children,
      );
    },
  );
}
