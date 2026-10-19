import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/local_server.dart';

void main() {
  test('download names survive quotes, backslashes and non-ASCII', () {
    expect(
      contentDisposition('report.pdf'),
      "attachment; filename=\"report.pdf\"; filename*=UTF-8''report.pdf",
    );
    // 따옴표·역슬래시가 quoted-string을 깨지 않음
    final tricky = contentDisposition('a"b\\');
    expect(tricky, startsWith('attachment; filename="a_b_";'));
    expect(tricky, endsWith("filename*=UTF-8''a%22b%5C"));
    // 한글은 ASCII 쪽에선 _, UTF-8 쪽에선 그대로 복원 가능
    final korean = contentDisposition("회의록 (최종)'s.txt");
    expect(korean, contains('filename="___ (__)\'s.txt"'));
    final encoded = korean.split("filename*=UTF-8''").last;
    expect(encoded, isNot(contains("'")));
    expect(encoded, isNot(contains('(')));
    expect(Uri.decodeComponent(encoded), "회의록 (최종)'s.txt");
    // 줄바꿈으로 헤더를 끼워 넣지 못함
    expect(contentDisposition('x\r\nSet-Cookie: a'), isNot(contains('\n')));
  });
}
