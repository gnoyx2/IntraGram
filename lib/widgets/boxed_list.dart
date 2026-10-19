import 'package:flutter/material.dart';

import 'package:intragram/theme/tokens.dart';

// Linux(libadwaita) 설정의 묶음 목록(boxed list): 한 절의 줄을 둥근 카드 하나에 담고 줄 사이를 실선으로
// 가름. 줄 강조는 각지게 두고 카드 모서리가 자름. 다른 OS는 줄을 그대로 늘어놓음
class BoxedList extends StatelessWidget {
  const BoxedList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.linux) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme.merge(
        shape: const RoundedRectangleBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, row) in children.indexed) ...[
              if (i > 0) const Divider(height: 1),
              row,
            ],
          ],
        ),
      ),
    );
  }
}
