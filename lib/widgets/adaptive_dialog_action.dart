import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// AlertDialog.adaptive는 Cupertino/Material 분기를 dart:io Platform이 아니라
// Theme.of(context).platform으로 정하므로 호출부도 그 값에서 뽑은 cupertino를 넘겨야 함
// 안 맞으면 CupertinoDialogAction이 슬라이드 제스처 코디네이터 없는 자리에 들어가 onPressed가
// 안 불리거나, 각진 Cupertino 칸에 둥근 Material 버튼이 끼어 모서리에 배경색이 안 맞는 조각이 남음
class AdaptiveDialogAction extends StatelessWidget {
  const AdaptiveDialogAction({
    required this.cupertino,
    required this.label,
    required this.onPressed,
    this.emphasis = false,
    this.destructive = false,
    this.icon,
    super.key,
  });

  final bool cupertino;
  final String label;
  final VoidCallback? onPressed;

  // 저장/이름 바꾸기/연결처럼 힘줘야 하는 액션. Cupertino는
  // isDefaultAction(굵게), Material은 FilledButton
  final bool emphasis;

  // 삭제/소거처럼 되돌릴 수 없는 액션. iOS 표준 빨간 글씨 / Material error 컬러
  final bool destructive;

  // Material에서만 씀 (Cupertino 액션엔 아이콘 관례가 없음)
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (cupertino) {
      return CupertinoDialogAction(
        isDefaultAction: emphasis,
        isDestructiveAction: destructive,
        // 기본 빨강(#FF3B30)은 반투명 대화상자 바탕에서 대비 약 2:1이라 진한 빨강으로 바꿈 (다크는 밝은 빨강)
        textStyle: destructive
            ? TextStyle(color: _readableRed.resolveFrom(context))
            : null,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    if (emphasis) {
      return icon == null
          ? FilledButton(onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            );
    }
    return TextButton(
      onPressed: onPressed,
      style: destructive
          ? TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      child: Text(label),
    );
  }
}

const _readableRed = CupertinoDynamicColor.withBrightness(
  color: Color(0xFF991B1B),
  darkColor: Color(0xFFFF6961),
);

// Windows(Fluent)는 주 동작이 맨 왼쪽, 닫기(취소)가 맨 오른쪽이라 Material 순서(닫기 … 주 동작)를 뒤집음.
// leading은 Material에서 맨 왼쪽에 따로 두는 중립 동작(PIN 지우기)으로, Windows에선 닫기 바로 앞
List<Widget> dialogActions(
  BuildContext context,
  List<Widget> actions, {
  Widget? leading,
}) {
  if (Theme.of(context).platform != TargetPlatform.windows) {
    return [?leading, ...actions];
  }
  final fluent = actions.reversed.toList();
  return [...fluent.take(fluent.length - 1), ?leading, fluent.last];
}

bool isCupertinoDialog(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}
