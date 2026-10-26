import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/image_viewer_screen.dart';

import '../support/contrast.dart';

// 1x1 투명 PNG (테스트용으로 진짜 디코드 가능한 이미지)
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('viewer_test');
    imagePath = '${tempDir.path}/tiny.png';
    await File(imagePath).writeAsBytes(_tinyPng);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('renders the image inside a pinch-zoomable viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageViewerScreen(path: imagePath)),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && find.byType(Image).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('dragging down past the threshold pops the route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImageViewerScreen(path: imagePath),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('imageViewerDismissListener')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a small drag snaps back instead of dismissing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageViewerScreen(path: imagePath)),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('imageViewerDismissListener')),
      const Offset(0, 30),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerScreen), findsOneWidget);
  });

  testWidgets('white photos keep both chrome bands shaded', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 1x2 불투명 흰 PNG라 여백 없이 화면을 꽉 채움
    await tester.runAsync(
      () => File(imagePath).writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAADklEQVR4nGP4DwQMIAIAJ+IH+dGbZDoAAAAASUVORK5CYII=',
        ),
      ),
    );
    const boundaryKey = Key('viewerPixels');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              padding: EdgeInsets.only(top: 44, bottom: 34),
            ),
            child: ImageViewerScreen(path: imagePath),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && find.byType(Image).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      await precacheImage(
        tester.widget<Image>(find.byType(Image)).image,
        tester.element(find.byType(Image)),
      );
    });
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    int red(int x, int y) => pixels!.getUint8((y * 320 + x) * 4);
    Color backgroundAt(int x, int y) => Color.fromARGB(
      255,
      red(x, y),
      pixels!.getUint8((y * 320 + x) * 4 + 1),
      pixels.getUint8((y * 320 + x) * 4 + 2),
    );
    expect(red(160, 320), 255);
    expect(red(160, 8), lessThan(255));
    expect(red(160, 632), lessThan(255));
    final close = find.byIcon(Icons.close);
    final filename = find.text('tiny.png');
    final iconInk = tester.widget<Icon>(close).color!;
    final filenameInk = tester.widget<Text>(filename).style!.color!;
    for (final y in [
      tester.getRect(close).top.ceil(),
      tester.getRect(close).bottom.floor() - 1,
    ]) {
      expect(
        contrastRatio(iconInk, backgroundAt(160, y)),
        greaterThanOrEqualTo(3),
      );
    }
    for (final y in [
      tester.getRect(filename).top.ceil(),
      tester.getRect(filename).bottom.floor() - 1,
    ]) {
      expect(
        contrastRatio(filenameInk, backgroundAt(300, y)),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('snap-back respects reduce motion: $reduceMotion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: ImageViewerScreen(path: imagePath),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('imageViewerDismissListener'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      double offset() => tester
          .widget<Transform>(
            find.byKey(const Key('imageViewerDismissTranslate')),
          )
          .transform
          .getTranslation()
          .y;
      expect(offset(), 30);
      await gesture.up();
      await tester.pump();
      expect(offset(), reduceMotion ? 0 : 30);
      await tester.pump(const Duration(milliseconds: 200));
      expect(offset(), 0);
      expect(find.byType(ImageViewerScreen), findsOneWidget);
    });
  }

  testWidgets(
    'a two-finger pinch never triggers the dismiss drag (#5 jitter fix)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ImageViewerScreen(path: imagePath)),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(
        find.byKey(const Key('imageViewerDismissListener')),
      );
      final gesture1 = await tester.startGesture(center - const Offset(20, 0));
      final gesture2 = await tester.startGesture(center + const Offset(20, 0));
      // 한 손가락이 닫기 스와이프처럼 보일 만큼 세로로 크게 움직여도 두 번째 포인터가 눌려 있는 동안엔 dismiss 드래그로 안 잡혀야 함.
      // Transform.translate 오프셋이 안 움직여야 함 (배경 튐 버그의 증상)
      await gesture1.moveBy(const Offset(0, 150));
      await tester.pump();
      final translate = tester
          .widget<Transform>(
            find.byKey(const Key('imageViewerDismissTranslate')),
          )
          .transform;
      expect(translate.getTranslation().y, 0);

      await gesture1.up();
      await gesture2.up();
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
    },
  );
}
