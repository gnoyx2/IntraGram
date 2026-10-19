import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';

part 'empty_state_art/bubbles_art.dart';
part 'empty_state_art/magnifier_art.dart';

enum EmptyStateArt { radar, bubbles, magnifier }

// 외부 SVG/이미지 패키지 없이 CustomPainter로 직접 그리는 벡터 일러스트
// 설계 좌표(preferredSize)로 그린 뒤 실제 크기에 맞춰 늘림
// motion을 주면 레이더가 그 값(0~1 반복)으로 스위프·펄스를 돌림. 위젯 리빌드 없이 다시 칠함
class EmptyStateArtPainter extends CustomPainter {
  const EmptyStateArtPainter({
    required this.art,
    required this.colorScheme,
    required this.chat,
    this.motion,
  }) : super(repaint: motion);

  final EmptyStateArt art;
  final ColorScheme colorScheme;
  final ChatColors chat;
  final Animation<double>? motion;

  static const Size radarSize = Size(160, 160);
  static const Size bubblesSize = Size(168, 128);
  static const Size magnifierSize = Size(148, 148);

  Size get preferredSize => switch (art) {
    EmptyStateArt.radar => radarSize,
    EmptyStateArt.bubbles => bubblesSize,
    EmptyStateArt.magnifier => magnifierSize,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final design = preferredSize;
    canvas.save();
    canvas.scale(size.width / design.width, size.height / design.height);
    switch (art) {
      case EmptyStateArt.radar:
        _paintRadar(canvas, motion?.value ?? 0.18);
      case EmptyStateArt.bubbles:
        _paintBubbles(canvas, colorScheme, chat);
      case EmptyStateArt.magnifier:
        _paintMagnifier(canvas, colorScheme);
    }
    canvas.restore();
  }

  // 동심원 3개 위로 반투명 스위프 빔이 돌고, 중심에서 펄스 링이 퍼짐
  // 빔이 지나간 자리의 피어 점은 잠깐 밝아졌다가 식음
  void _paintRadar(Canvas canvas, double phase) {
    const center = Offset(80, 80);
    const rim = 72.0;
    final accent = colorScheme.primary;
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (radius, alpha) in const [(26.0, 0.20), (49.0, 0.15)]) {
      canvas.drawCircle(
        center,
        radius,
        guide..color = accent.withValues(alpha: alpha),
      );
    }
    canvas.drawCircle(
      center,
      rim,
      guide..color = accent.withValues(alpha: 0.1),
    );
    guide.color = accent.withValues(alpha: 0.06);
    canvas.drawLine(const Offset(8, 80), const Offset(152, 80), guide);
    canvas.drawLine(const Offset(80, 8), const Offset(80, 152), guide);

    const span = 1.1;
    final heading = phase * 2 * math.pi - math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: rim);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, heading - span, span, false)
        ..close(),
      Paint()
        ..shader = SweepGradient(
          endAngle: span,
          colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.3)],
          transform: GradientRotation(heading - span),
        ).createShader(rect),
    );
    canvas.drawLine(
      center,
      center + Offset.fromDirection(heading, rim),
      Paint()
        ..color = accent.withValues(alpha: 0.65)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    final pulse = (phase * 2) % 1;
    canvas.drawCircle(
      center,
      8 + pulse * (rim - 8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: (1 - pulse) * 0.4),
    );

    for (final (radius, degrees) in const [
      (49.0, -150.0),
      (72.0, -32.0),
      (26.0, 64.0),
      (60.0, 128.0),
    ]) {
      final angle = degrees * math.pi / 180;
      final behind = (heading - angle) % (2 * math.pi);
      final glow = math.max(0.0, 1 - behind / 2.2);
      final blip = center + Offset.fromDirection(angle, radius);
      canvas.drawCircle(
        blip,
        7,
        Paint()..color = accent.withValues(alpha: 0.16 * glow),
      );
      canvas.drawCircle(
        blip,
        3.2,
        Paint()
          ..color = Color.lerp(
            colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            accent,
            glow,
          )!,
      );
    }

    canvas.drawCircle(
      center,
      12,
      Paint()..color = accent.withValues(alpha: 0.16),
    );
    canvas.drawCircle(center, 6.5, Paint()..color = accent);
    canvas.drawCircle(center, 2.4, Paint()..color = colorScheme.onPrimary);
  }

  @override
  bool shouldRepaint(EmptyStateArtPainter oldDelegate) =>
      oldDelegate.art != art ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.chat != chat ||
      oldDelegate.motion != motion;
}
