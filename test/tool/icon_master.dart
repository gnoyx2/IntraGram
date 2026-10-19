// 아이콘 마스터 생성기. _test 접미사가 없어 일반 테스트 실행에는 안 잡힘
// flutter test test/tool/icon_master.dart && ./tool/gen_icons.sh
// build/icon_master/에 1024px PNG 여섯 장과 작은 PNG 세 장을 쓰고 gen_icons.sh가 플랫폼별로 줄임
// - master_full: 풀블리드 배경 + 마크 (Android 레거시, iOS. 모서리는 OS가 깎음)
// - master_macos: Big Sur 스퀘어클 플레이트 + 투명 여백 (macOS, Linux)
// - master_windows: 캔버스를 거의 채우는 스퀘어클 플레이트 (Windows 48px 이상)
// - small_16/24/32: 픽셀 격자에 맞춘 두 노드 빔 마크 (Windows 작은 크기)
// - foreground / monochrome: Android 어댑티브·테마 아이콘 전경 (66dp 안전 원 안)
// - launch_mark: 투명 배경 런치 화면 마크
// - notification: Android 알림 small icon(흰 실루엣, 마크가 폭의 92%)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'icon_painter.dart';

void main() {
  testWidgets('generate and validate all icon masters', (tester) async {
    // 엔진 래스터 콜백이 실제 비동기 영역에서 끝나게 runAsync 안에서 돌림
    await tester.runAsync(() async {
      final outDir = Directory('build/icon_master')
        ..createSync(recursive: true);
      for (final variant in [
        'master_full',
        'master_macos',
        'master_windows',
        'foreground',
        'monochrome',
        'launch_mark',
        'notification',
      ]) {
        final image = await _render(variant);
        await _verify(image, variant);
        await _write(image, '${outDir.path}/$variant.png');
      }
      for (final size in const [16, 24, 32]) {
        final recorder = ui.PictureRecorder();
        paintSmallIcon(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        picture.dispose();
        await _verifySmall(image, size);
        await _write(image, '${outDir.path}/small_$size.png');
      }
    });
  });
}

Future<ui.Image> _render(String variant) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 1024, 1024);
  switch (variant) {
    case 'master_full':
      paintIconBackground(canvas, bounds);
      paintPeerMark(canvas, glow: true);
    case 'master_macos':
      paintMacosPlate(canvas);
    case 'master_windows':
      paintWindowsPlate(canvas);
    case 'notification':
      // 상태 표시줄은 알파만 써서 흰색으로 칠함. 24dp 안에서 보이게 마크를 캔버스 폭에 맞춰 키움
      const scale = 1024 * 0.92 / 800;
      canvas
        ..translate(512, 512)
        ..scale(scale)
        ..translate(-512, -512);
      paintPeerMark(canvas, monochrome: true);
    default:
      // 어댑티브 아이콘 마크 전체가 108dp 캔버스 중앙 66dp 안전 원 안에 들어가게 줄임
      final scale = variant == 'launch_mark' ? 0.84 : 0.72;
      final inset = (1024 - 1024 * scale) / 2;
      canvas.translate(inset, inset);
      canvas.scale(scale);
      paintPeerMark(canvas, monochrome: variant == 'monochrome');
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1024, 1024);
  picture.dispose();
  return image;
}

Future<void> _verify(ui.Image image, String variant) async {
  expect(image.width, 1024);
  expect(image.height, 1024);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var opaquePixels = 0;
  var outsideSafeCircle = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    final alpha = bytes[i + 3];
    if (variant == 'master_full') expect(alpha, 255);
    if (alpha == 0) continue;
    opaquePixels++;
    if (variant == 'monochrome' || variant == 'notification') {
      expect(bytes[i], alpha);
      expect(bytes[i + 1], alpha);
      expect(bytes[i + 2], alpha);
      if (variant == 'notification') continue;
      final x = (i ~/ 4) % 1024 - 512;
      final y = (i ~/ 4) ~/ 1024 - 512;
      if (x * x + y * y > 313 * 313) outsideSafeCircle++;
    }
  }
  expect(opaquePixels, greaterThan(20000));
  if (variant != 'master_full') expect(bytes[3], 0);
  if (variant == 'monochrome') expect(outsideSafeCircle, 0);
}

Future<void> _write(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}

// 모서리는 판 밖이라 투명하고, 빔 가운데와 두 노드 중심은 불투명한 밝은 색이어야 함
Future<void> _verifySmall(ui.Image image, int size) async {
  expect(image.width, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  int at(int x, int y, int channel) => bytes[(y * size + x) * 4 + channel];
  expect(at(0, 0, 3), 0);
  final y = size ~/ 2 - 1;
  for (final x in [size ~/ 4, size ~/ 2, size * 3 ~/ 4 - 1]) {
    expect(at(x, y, 3), 255, reason: '$size px at $x,$y');
    expect(at(x, y, 1), greaterThan(150), reason: '$size px at $x,$y');
  }
}
