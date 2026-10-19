import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 화면 코드의 여백·간격·반경은 AppSpacing·AppRadius 토큰만 씀
// 숫자 하나만 넣은 인자(0 제외)를 잡음. 계산식, 가로세로를 다 정한 컴포넌트 크기,
// 일러스트 좌표(empty_state_art)는 대상이 아님
final _call = RegExp(
  r'\b(?:EdgeInsets(?:Directional)?\.\w+|BorderRadius\.circular|'
  r'Radius\.circular|SizedBox)\(',
);
final _literal = RegExp(r'^(?:\w+:\s*)?(\d+(?:\.\d+)?)$');
final _gap = RegExp(r'^(?:width|height):');
final _spacing = RegExp(r'\b(?:spacing|runSpacing):\s*(\d+(?:\.\d+)?)\b');

void main() {
  test('spacing and radii in lib/ come from the design tokens', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') && !f.path.contains('empty_state_art'),
        );
    for (final file in files) {
      final src = file.readAsStringSync();
      String at(int offset) =>
          '${file.path}:${'\n'.allMatches(src.substring(0, offset)).length + 1}';
      for (final call in _call.allMatches(src)) {
        final args = _topLevelArgs(src, call.end - 1);
        // SizedBox는 width나 height 하나만 둔 간격 상자만 봄
        final gapBox = args.length == 1 && _gap.hasMatch(args.single);
        if (call[0] == 'SizedBox(' && !gapBox) continue;
        for (final arg in args) {
          final number = _literal.firstMatch(arg)?[1];
          if (number != null && double.parse(number) != 0) {
            offenders.add('${at(call.start)} ${call[0]}$arg)');
          }
        }
      }
      for (final named in _spacing.allMatches(src)) {
        if (double.parse(named[1]!) != 0) offenders.add(at(named.start));
      }
    }
    expect(offenders, isEmpty);
  });
}

// 여는 괄호부터 짝이 맞는 닫는 괄호까지를 최상위 쉼표로 자름
List<String> _topLevelArgs(String src, int open) {
  final args = <String>[];
  var depth = 0;
  var start = open + 1;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 0 || (depth == 1 && c == ',')) {
      final arg = src.substring(start, i).trim();
      if (arg.isNotEmpty) args.add(arg);
      start = i + 1;
    }
    if (depth == 0) break;
  }
  return args;
}
