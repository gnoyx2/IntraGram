import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/image_viewer_screen.dart';
import 'package:intragram/l10n/strings.dart';

// 받은 이미지 공유(파일 앱·드라이브로 꺼내기)는 폰·태블릿에만 둠: 데스크톱은 이미 사용자가 고른 폴더에 저장됨
// 플랫폼은 테스트를 돌리는 호스트가 아니라 대상 플랫폼으로 정해서 양쪽 다 여기서 확인함
void main() {
  const en = S(AppLang.en);
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_viewer_share');
    path = '${dir.path}/tiny.png';
    // 1x1 투명 PNG
    File(path).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets(
    'a phone offers Share',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: ImageViewerScreen(path: path)));
      expect(find.byTooltip(en.t('viewer.share')), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('a desktop has only Close', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageViewerScreen(path: path)));
    expect(find.byTooltip(en.t('viewer.share')), findsNothing);
    expect(find.byTooltip(en.t('viewer.close')), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());
}
