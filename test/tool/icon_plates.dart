part of 'icon_painter.dart';

// Big Sur 템플릿: 1024 캔버스 안 824 플레이트, 연속 곡률 모서리
void paintMacosPlate(Canvas canvas) => _paintPlate(
  canvas,
  const Rect.fromLTWH(100, 100, 824, 824),
  const Radius.circular(185),
  dropShadow: true,
);

// Windows 작업 표시줄·탐색기용. 다른 앱 아이콘처럼 캔버스를 거의 채워서 각진 타일로 안 보임
// 모서리는 macOS와 같은 비율(185/824), 판 밖 그림자는 여백이 좁아서 뺌
void paintWindowsPlate(Canvas canvas) => _paintPlate(
  canvas,
  const Rect.fromLTWH(64, 64, 896, 896),
  const Radius.circular(201),
);

void _paintPlate(
  Canvas canvas,
  Rect rect,
  Radius radius, {
  bool dropShadow = false,
}) {
  final plate = RSuperellipse.fromRectAndRadius(rect, radius);
  final platePath = Path()..addRSuperellipse(plate);
  if (dropShadow) {
    canvas.drawPath(
      platePath.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }
  canvas.save();
  canvas.clipRSuperellipse(plate);
  paintIconBackground(canvas, rect);
  // 위쪽 안쪽 하이라이트와 아래쪽 안쪽 그림자로 판이 살짝 들려 보이게 함
  canvas.drawPath(
    platePath.shift(const Offset(0, 6)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawPath(
    platePath.shift(const Offset(0, -8)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width / 1024);
  paintPeerMark(canvas, glow: true);
  canvas.restore();
  canvas.drawRSuperellipse(
    plate,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.08),
  );
}

// 16~32px 전용 단순 마크. 쉴드·글로우는 이 크기에서 뭉개져서 빼고 두 노드와 빔만
// 정수 픽셀에 맞춰 그림 (16px 기준 판 여백 1, 노드 지름 4, 빔 두께 2)
void paintSmallIcon(Canvas canvas, int size) {
  final unit = size / 16;
  final inset = unit.roundToDouble();
  final plateRect = Rect.fromLTWH(
    inset,
    inset,
    size - inset * 2,
    size - inset * 2,
  );
  canvas.save();
  canvas.clipRSuperellipse(
    RSuperellipse.fromRectAndRadius(
      plateRect,
      Radius.circular(plateRect.width * 185 / 824),
    ),
  );
  paintIconBackground(canvas, plateRect);
  canvas.restore();
  final beam = (unit * 2).roundToDouble();
  final top = ((size - beam) / 2).floorToDouble();
  final left = Offset(size * 0.25, top + beam / 2);
  final right = Offset(size * 0.75, top + beam / 2);
  canvas.drawRect(
    Rect.fromLTRB(left.dx, top, right.dx, top + beam),
    _linear(left, right, [_cyan, _mint]),
  );
  final node = (unit * 2).roundToDouble();
  canvas.drawCircle(left, node, Paint()..color = _sky);
  canvas.drawCircle(right, node, Paint()..color = _mint);
}
