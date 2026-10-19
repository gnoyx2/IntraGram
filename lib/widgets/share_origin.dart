import 'package:flutter/widgets.dart';

// iPad 공유 팝오버 화살표가 누른 버튼을 가리키게 하는 기준 사각형 (iPhone·Android는 안 씀)
// 안 주면 share_plus가 화면 가운데를 기준으로 잡음
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
