part of '../empty_state_art.dart';

// 겹친 두 말풍선(상대가 뒤, 내가 앞)과 앞 말풍선 모서리에 걸친 자물쇠 배지
void _paintBubbles(Canvas canvas, ColorScheme scheme, ChatColors chat) {
  const round = Radius.circular(AppRadius.lg);
  const tail = Radius.circular(AppRadius.tail);
  final soft = Paint()
    ..color = Colors.black.withValues(alpha: 0.07)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  final theirs = RRect.fromRectAndCorners(
    const Rect.fromLTRB(12, 12, 112, 64),
    topLeft: round,
    topRight: round,
    bottomRight: round,
    bottomLeft: tail,
  );
  canvas.drawRRect(theirs.shift(const Offset(0, 3)), soft);
  canvas.drawRRect(theirs, Paint()..color = chat.bubbleTheirs);
  canvas.drawRRect(
    theirs,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.outlineVariant,
  );
  _textLines(canvas, const Offset(26, 28), const [
    60,
    40,
  ], chat.onBubbleTheirs.withValues(alpha: 0.16));

  const mineRect = Rect.fromLTRB(52, 56, 152, 108);
  final mine = RRect.fromRectAndCorners(
    mineRect,
    topLeft: round,
    topRight: round,
    bottomLeft: round,
    bottomRight: tail,
  );
  canvas.drawRRect(mine.shift(const Offset(0, 4)), soft);
  canvas.drawRRect(
    mine,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [chat.bubbleMineTop, chat.bubbleMine],
      ).createShader(mineRect),
  );
  canvas.drawRRect(
    mine,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = chat.bubbleMineEdge,
  );
  _textLines(canvas, const Offset(66, 72), const [
    62,
    34,
  ], chat.onBubbleMine.withValues(alpha: 0.2));

  const badge = Offset(148, 56);
  canvas.drawCircle(badge.translate(0, 2), 16, soft);
  canvas.drawCircle(badge, 16, Paint()..color = chat.online);
  _paintLock(
    canvas,
    badge,
    scheme.brightness == Brightness.dark ? scheme.surface : Colors.white,
    chat.online,
  );
}

void _textLines(
  Canvas canvas,
  Offset origin,
  List<double> widths,
  Color color,
) {
  final paint = Paint()..color = color;
  for (var i = 0; i < widths.length; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy + i * 13, widths[i], 6),
        const Radius.circular(3),
      ),
      paint,
    );
  }
}

// 고리와 몸통, 열쇠 구멍만 남긴 미니멀 자물쇠. center는 배지 중심
void _paintLock(Canvas canvas, Offset center, Color ink, Color hole) {
  final shackle = Rect.fromCenter(
    center: center.translate(0, -3),
    width: 9,
    height: 10,
  );
  canvas.drawPath(
    Path()
      ..moveTo(shackle.left, center.dy)
      ..lineTo(shackle.left, shackle.center.dy)
      ..arcTo(shackle, math.pi, math.pi, false)
      ..lineTo(shackle.right, center.dy),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = ink,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, 3.5), width: 14, height: 10),
      const Radius.circular(2.5),
    ),
    Paint()..color = ink,
  );
  canvas.drawCircle(center.translate(0, 3), 1.6, Paint()..color = hole);
}
