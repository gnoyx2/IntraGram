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

  // 카메라도 사진첩도 모바일 전용(데스크톱엔 진짜 사진첩이 없어서 file_picker
  // 파일 브라우저와 똑같아 보임): 둘 다 이 (비모바일) 테스트 호스트에선
  // 숨겨짐. photoLibrary 선택 자체는 desktop이 아닌 실기기에서만 검증 가능
  testWidgets(
    'camera and photo library are hidden on this (non-mobile) test platform',
    (tester) async {
      await tester.pumpWidget(_harness((_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Photo Library'), findsNothing);
      expect(find.text('File'), findsOneWidget);
    },
  );
}
