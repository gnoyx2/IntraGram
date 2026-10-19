import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/settings/privacy_screen.dart';
import 'package:intragram/l10n/strings.dart';

// 번역 테이블은 손으로 맞춰서, 키를 하나 빠뜨리면 한국어 화면에 영어가 조용히 섞임(S.t가 영어로 폴백).
// 두 테이블의 키·자리표시자가 같고, 모든 키를 코드가 쓰고, 코드가 부르는 키는 다 있는지 고정함

final RegExp _placeholder = RegExp(r'\{(\w+)\}');

Set<String> _placeholders(String value) =>
    _placeholder.allMatches(value).map((m) => m.group(1)!).toSet();

// lib의 Dart 소스 (번역 테이블 자체는 뺌)
String _libSource() => [
  for (final f in Directory('lib').listSync(recursive: true))
    if (f is File &&
        f.path.endsWith('.dart') &&
        !f.path.contains('l10n/translations'))
      f.readAsStringSync(),
].join('\n');

void main() {
  final en = S.tableOf(AppLang.en);
  final ko = S.tableOf(AppLang.ko);

  test('English and Korean have the same keys and placeholders', () {
    expect(ko.keys.toSet().difference(en.keys.toSet()), isEmpty);
    expect(en.keys.toSet().difference(ko.keys.toSet()), isEmpty);
    for (final key in en.keys) {
      expect(_placeholders(ko[key]!), _placeholders(en[key]!), reason: key);
    }
  });

  test('every key is used and every looked-up key exists', () {
    final source = _libSource();
    // 개인정보 화면만 절 이름으로 키를 조합함
    final composed = {
      for (final section in PrivacyScreen.sections) ...[
        'privacy.${section}Title',
        'privacy.${section}Body',
      ],
    };
    final unused = en.keys
        .where((k) => !composed.contains(k) && !source.contains("'$k'"))
        .toList();
    expect(unused, isEmpty, reason: 'defined but never used');

    final looked = RegExp(
      r"\.t\(\s*'([\w.]+)'",
    ).allMatches(source).map((m) => m.group(1)!);
    expect(looked.where((k) => !en.containsKey(k)).toSet(), isEmpty);
  });
}
