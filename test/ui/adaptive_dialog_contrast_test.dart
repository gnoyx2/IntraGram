import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

// iOS 대화상자의 되돌릴 수 없는 동작(숫자가 달라요·삭제)은 빨간 글씨인데, 기본 빨강(#FF3B30)은 반투명
// 대화상자 바탕에서 대비가 약 2.5:1이라 읽기 어려웠음. 라이트·다크 모두 글자 대비 기준을 넘김
void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('${theme.brightness.name}: a destructive Cupertino action is '
        'readable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(platformBrightness: theme.brightness),
              child: CupertinoTheme(
                data: CupertinoThemeData(brightness: theme.brightness),
                child: CupertinoAlertDialog(
                  title: const Text('Codes'),
                  actions: [
                    AdaptiveDialogAction(
                      cupertino: true,
                      label: 'Codes differ',
                      destructive: true,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  }
}
