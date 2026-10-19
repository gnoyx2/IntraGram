// 해상도에 독립적인 피어 링크와 보안 쉴드 마크를 1024 좌표계에 그림
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

part 'icon_plates.dart';

const iconObsidian = Color(0xFF080E1A);
const _navy = Color(0xFF102038);
const _deep = Color(0xFF0C182A);
const _mint = Color(0xFF00F5D4);
const _cyan = Color(0xFF38BDF8);
const _crystal = Color(0xFFF6FDFF);
const _frost = Color(0xFFBAE6FD);
const _sky = Color(0xFF7DD3FC);
const _foam = Color(0xFFCCFBF1);
const _teal = Color(0xFF00BFA6);

const _leftNode = Offset(198, 512);
const _rightNode = Offset(826, 512);
const _nodeRadius = 68.0;
const _markBounds = Rect.fromLTWH(112, 300, 800, 424);

void paintIconBackground(Canvas canvas, Rect rect) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [iconObsidian, _navy, _deep],
        [0, 0.5, 1],
      ),
  );
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(rect.center, rect.width * 0.52, [
        _cyan.withValues(alpha: 0.22),
        _cyan.withValues(alpha: 0),
      ]),
  );
  // 근거리 범위를 떠올리게 하는 동심원. 작은 크기에선 사라질 만큼만 옅게 둠
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = rect.width * 0.0025
    ..color = _crystal.withValues(alpha: 0.05);
  for (final factor in const [0.31, 0.41]) {
    canvas.drawCircle(rect.center, rect.width * factor, ring);
  }
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.center, [
        Colors.white.withValues(alpha: 0.06),
        Colors.white.withValues(alpha: 0),
      ]),
  );
}

// 위가 뾰족한 클래식 쉴드. 512를 축으로 좌우 대칭임
Path _shieldPath() => Path()
  ..moveTo(512, 322)
  ..cubicTo(560, 352, 618, 368, 664, 372)
  ..lineTo(664, 496)
  ..cubicTo(664, 600, 602, 664, 512, 702)
  ..cubicTo(422, 664, 360, 600, 360, 496)
  ..lineTo(360, 372)
  ..cubicTo(406, 368, 464, 352, 512, 322)
  ..close();

// 두 노드 중심을 잇는 캡슐
Path _beamPath(double halfWidth) => Path()
  ..addRRect(
    RRect.fromLTRBR(
      _leftNode.dx,
      _leftNode.dy - halfWidth,
      _rightNode.dx,
      _rightNode.dy + halfWidth,
      Radius.circular(halfWidth),
    ),
  );

Path _keyholePath() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(512, 478), radius: 40))
  ..addRRect(RRect.fromLTRBR(491, 486, 533, 596, const Radius.circular(21)));

void paintPeerMark(
  Canvas canvas, {
  bool monochrome = false,
  bool glow = false,
}) {
  final beam = _beamPath(23);
  final shield = _shieldPath();
  if (glow) _paintGlow(canvas, beam, shield);

  final clear = Paint()..blendMode = BlendMode.clear;
  canvas.saveLayer(_markBounds, Paint());
  canvas.drawPath(
    beam,
    monochrome ? _white : _linear(_leftNode, _rightNode, [_cyan, _mint]),
  );
  // 빔 가운데 밝은 심선으로 빛줄기처럼 보이게 함
  if (!monochrome) {
    canvas.drawPath(
      _beamPath(7),
      Paint()
        ..color = _crystal.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }
  canvas.drawCircle(
    _leftNode,
    _nodeRadius,
    monochrome ? _white : _orb(_leftNode, [_crystal, _sky, _cyan]),
  );
  canvas.drawCircle(
    _rightNode,
    _nodeRadius,
    monochrome ? _white : _orb(_rightNode, [_foam, _mint, _teal]),
  );
  // 쉴드 둘레를 투명하게 파서 빔과 쉴드가 단색 테마에서도 붙어 보이지 않게 함
  canvas.drawPath(
    shield,
    Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 36,
  );
  canvas.drawPath(
    shield,
    monochrome
        ? _white
        : _linear(const Offset(512, 322), const Offset(512, 702), [
            _crystal,
            _frost,
          ]),
  );
  if (!monochrome) _paintFacet(canvas, shield);
  canvas.drawPath(_keyholePath(), clear);
  canvas.restore();
}

final _white = Paint()..color = Colors.white;

Paint _linear(Offset from, Offset to, List<Color> colors) =>
    Paint()..shader = ui.Gradient.linear(from, to, colors);

// 왼쪽 위에서 빛을 받는 구슬처럼 노드를 칠함
Paint _orb(Offset center, List<Color> colors) => Paint()
  ..shader = ui.Gradient.radial(
    center.translate(-_nodeRadius * 0.35, -_nodeRadius * 0.4),
    _nodeRadius * 1.5,
    colors,
    const [0, 0.55, 1],
  );

// 쉴드 오른쪽 절반에 옅은 사이언을 얹어 크리스털 면처럼 보이게 함
void _paintFacet(Canvas canvas, Path shield) {
  canvas.save();
  canvas.clipRect(const Rect.fromLTRB(512, 300, 700, 720));
  canvas.drawPath(
    shield,
    Paint()
      ..blendMode = BlendMode.srcATop
      ..color = _cyan.withValues(alpha: 0.22),
  );
  canvas.restore();
}

void _paintGlow(Canvas canvas, Path beam, Path shield) {
  canvas.drawPath(
    beam,
    Paint()
      ..color = _cyan.withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
  );
  for (final (node, color) in const [(_leftNode, _cyan), (_rightNode, _mint)]) {
    canvas.drawCircle(
      node,
      _nodeRadius + 12,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }
  canvas.drawPath(
    shield,
    Paint()
      ..color = _crystal.withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
  );
}
