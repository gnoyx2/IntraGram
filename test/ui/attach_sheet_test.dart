import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/attach_sheet.dart';

Widget _harness(ValueChanged<Future<AttachChoice?>> onOpen) {
  return MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => onOpen(showAttachSheet(context)),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping File resolves file', (tester) async {
    AttachChoice? result;
    await tester.pumpWidget(
      _harness((future) => future.then((v) => result = v)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(result, AttachChoice.file);
  });

  // 사진첩은 모바일 전용(데스크톱엔 진짜 사진첩이 없어서 file_picker 파일 브라우저와 똑같아 보임)
  // 플랫폼은 테스트를 돌리는 호스트가 아니라 대상 플랫폼으로 정해서 양쪽 다 여기서 확인함
  testWidgets(
    'a phone offers the photo library',
    (tester) async {
      AttachChoice? result;
      await tester.pumpWidget(
        _harness((future) => future.then((v) => result = v)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo Library'));
      await tester.pumpAndSettle();
      expect(result, AttachChoice.photoLibrary);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'a desktop offers no camera or photo library',
    (tester) async {
      await tester.pumpWidget(_harness((_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Photo Library'), findsNothing);
      expect(find.text('File'), findsOneWidget);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
