import 'dart:ui';

// WCAG 2 대비. 반투명 글자는 바탕에 먼저 합성한 뒤 잼
double contrastRatio(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background).computeLuminance();
  final bg = background.computeLuminance();
  final (high, low) = fg > bg ? (fg, bg) : (bg, fg);
  return (high + 0.05) / (low + 0.05);
}
