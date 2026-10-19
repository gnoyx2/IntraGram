import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/punycode.dart';

// 링크 확인 대화상자가 보여 줄 호스트: 브라우저 주소창처럼 비ASCII 라벨을 xn--로 드러냄 (RFC 3492 예시 값)
void main() {
  test('non-ASCII labels become xn-- like in an address bar', () {
    expect(asciiHost('münchen.de'), 'xn--mnchen-3ya.de');
    expect(asciiHost('bücher.example'), 'xn--bcher-kva.example');
    expect(asciiHost('пример.рф'), 'xn--e1afmkfd.xn--p1ai');
    expect(asciiHost('例え.jp'), 'xn--r8jz45g.jp');
    expect(asciiHost('аpple.com'), 'xn--pple-43d.com', reason: 'Cyrillic а');
  });

  test('plain hosts only get lower-cased', () {
    expect(asciiHost('Example.COM'), 'example.com');
    expect(asciiHost('192.168.1.9'), '192.168.1.9');
  });
}
