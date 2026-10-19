part of '../empty_state_art.dart';

// 유리 렌즈 돋보기. 렌즈 안 글줄은 한 단계 크게 보이고, 테는 그라디언트, 왼쪽 위에 반사광
void _paintMagnifier(Canvas canvas, ColorScheme scheme) {
  const lens = Offset(62, 60);
  const radius = 36.0;
  final accent = scheme.primary;
  final lensRect = Rect.fromCircle(center: lens, radius: radius);
  final reach = Offset.fromDirection(math.pi / 4);

  final handleStart = lens + reach * (radius + 4);
  final handleEnd = lens + reach * (radius + 46);
  canvas.drawLine(
    handleStart,
    handleEnd,
    Paint()
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [accent, Color.lerp(accent, Colors.black, 0.25) ?? accent],
      ).createShader(Rect.fromPoints(handleStart, handleEnd)),
  );
  canvas.drawLine(
    lens + reach * (radius + 1),
    lens + reach * (radius + 10),
    Paint()
      ..strokeWidth = 9
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.5),
  );

  canvas.drawCircle(
    lens,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.04),
          accent.withValues(alpha: 0.16),
        ],
      ).createShader(lensRect),
  );
  canvas.save();
  canvas.clipPath(Path()..addOval(lensRect.deflate(3)));
  final ink = Paint()..color = scheme.onSurfaceVariant.withValues(alpha: 0.3);
  for (final (width, top) in const [(46.0, 44.0), (34.0, 58.0), (24.0, 72.0)]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(40, top, width, 7),
        const Radius.circular(3.5),
      ),
      ink,
    );
  }
  canvas.restore();

  canvas.drawCircle(
    lens,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..shader = SweepGradient(
        colors: [accent, accent.withValues(alpha: 0.55), accent],
      ).createShader(lensRect),
  );
  canvas.drawCircle(
    lens,
    radius - 4.5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.35),
  );
  canvas.drawArc(
    Rect.fromCircle(center: lens, radius: radius - 11),
    math.pi * 1.05,
    math.pi * 0.32,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.7),
  );
  _paintSparkle(
    canvas,
    const Offset(116, 24),
    7,
    accent.withValues(alpha: 0.5),
  );
  _paintSparkle(
    canvas,
    const Offset(128, 44),
    4,
    accent.withValues(alpha: 0.3),
  );
}

// 네 꼭짓점이 오목하게 휜 반짝임
void _paintSparkle(Canvas canvas, Offset c, double r, Color color) {
  canvas.drawPath(
    Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close(),
    Paint()..color = color,
  );
}
