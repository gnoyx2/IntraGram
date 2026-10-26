import 'dart:math' show min;

// 링크 확인 창용 호스트 표기: 비ASCII 라벨을 퓨니코드(xn--, RFC 3492)로 바꿔 'аpple.com'(키릴 а) 같은 동형 문자 주소를 드러냄.
// UTS #46 매핑·NFC 없이 소문자만 맞춤. 표시 전용이라 드문 문자에서 브라우저와 달라도 'xn--' 신호는 같고, 실제로 여는 건 원문 URL
String asciiHost(String host) => host
    .split('.')
    .map((label) {
      final lower = label.toLowerCase();
      return lower.runes.every((r) => r < 0x80)
          ? lower
          : 'xn--${_punycode(lower)}';
    })
    .join('.');

const _base = 36, _tMin = 1, _tMax = 26, _skew = 38, _damp = 700;

String _punycode(String label) {
  final points = label.runes.toList();
  final out = StringBuffer()
    ..writeAll(points.where((c) => c < 0x80).map(String.fromCharCode));
  final basic = out.length;
  if (basic > 0) out.write('-');
  var n = 0x80, delta = 0, bias = 72, handled = basic;
  while (handled < points.length) {
    final next = points.where((c) => c >= n).reduce(min);
    delta += (next - n) * (handled + 1);
    n = next;
    for (final c in points) {
      if (c < n) delta++;
      if (c != n) continue;
      var q = delta;
      for (var k = _base; ; k += _base) {
        final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
        if (q < t) break;
        out.write(_digit(t + (q - t) % (_base - t)));
        q = (q - t) ~/ (_base - t);
      }
      out.write(_digit(q));
      bias = _adapt(delta, handled + 1, first: handled == basic);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return out.toString();
}

// 0..25 = a..z, 26..35 = 0..9
String _digit(int d) => String.fromCharCode(d < 26 ? 0x61 + d : 0x16 + d);

int _adapt(int delta, int points, {required bool first}) {
  var d = first ? delta ~/ _damp : delta ~/ 2;
  d += d ~/ points;
  var k = 0;
  while (d > ((_base - _tMin) * _tMax) ~/ 2) {
    d ~/= _base - _tMin;
    k += _base;
  }
  return k + (_base - _tMin + 1) * d ~/ (d + _skew);
}
