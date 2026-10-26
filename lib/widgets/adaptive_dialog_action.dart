import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/theme/tokens.dart';

// 이 높이보다 낮게 보이는 창(키보드가 올라온 플로팅 창 등)은 대화상자 위아래 여백을 줄임
const _kCompactDialogHeight = 480.0;

// AlertDialog.adaptive 대신 씀. Cupertino 여부를 버튼과 같은 cupertino 값(isCupertinoDialog)으로 정하고,
// Material 쪽은 제목·본문이 스크롤돼서 키보드가 올라온 작은 창에서도 넘치지 않음
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    required this.cupertino,
    this.icon,
    this.title,
    this.content,
    this.actions,
    super.key,
  });

  final bool cupertino;
  // Material에서만 씀 (Cupertino 대화상자엔 아이콘 칸이 없음)
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    if (cupertino) {
      return CupertinoAlertDialog(
        title: title,
        content: content,
        actions: actions ?? const <Widget>[],
      );
    }
    final visible =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final compact = visible < _kCompactDialogHeight;
    final buttons = actions;
    return AlertDialog(
      icon: icon,
      title: title,
      // 낮은 창에선 버튼도 본문과 같이 스크롤함: 큰 글씨로 버튼이 세로로 쌓이면 버튼만으로 창 높이를 넘음
      content: compact && buttons != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?content,
                const SizedBox(height: AppSpacing.lg),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: AppSpacing.sm,
                  children: buttons,
                ),
              ],
            )
          : content,
      actions: compact ? null : buttons,
      scrollable: true,
      insetPadding: compact
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            )
          : null,
    );
  }
}

// AppAlertDialog는 Cupertino/Material 분기를 dart:io Platform이 아니라 isCupertinoDialog로 정하므로
// 호출부도 같은 값을 넘겨야 함. 안 맞으면 CupertinoDialogAction이 슬라이드 제스처 코디네이터 없는 자리에
// 들어가 onPressed가 안 불리거나, 각진 Cupertino 칸에 둥근 Material 버튼이 끼어 모서리에 배경색이 안 맞는 조각이 남음
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

  // 저장·이름 바꾸기·연결처럼 강조할 주 동작 여부임 (Cupertino는 굵게, Material은 FilledButton)
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

// iOS·macOS라도 투명도 줄이기·대비 높이기를 켰으면 Material 쪽을 씀: Cupertino 대화상자 바탕은 반투명 유리로
// 고정이라, 앱 테마의 불투명 바탕·선명한 경계로 그림 (설정이 바뀌면 다음에 여는 대화상자부터)
bool isCupertinoDialog(BuildContext context) {
  final platform = Theme.of(context).platform;
  return (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) &&
      !OsPrivacy.reduceTransparency.value &&
      !OsPrivacy.highContrast.value &&
      !MediaQuery.highContrastOf(context);
}
