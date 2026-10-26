import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/core/path_safety.dart';
import 'package:intragram/core/path_safety_names.dart';

int _utf8Length(String value) => utf8.encode(value).length;

void main() {
  group('safeBasename', () {
    test('strips directory parts and mixed separators', () {
      expect(safeBasename('a/b/c.txt'), 'c.txt');
      expect(safeBasename(r'a\b/c.txt'), 'c.txt');
      expect(safeBasename('../../../etc/passwd'), 'passwd');
    });

    // 받는 쪽은 제안 때 한 번, 저장할 때 또 한 번 거름: 두 번째에 이름이 바뀌면 카드엔 .e로 뜨고 .exe로 저장됨
    test('cleaning an already clean name changes nothing', () {
      for (final raw in ['${'A' * 187}invoice.ex.ZZZZ.e', '.${'A' * 250}']) {
        final once = safeBasename(raw);
        expect(safeBasename(once), once, reason: raw);
        expect(_utf8Length(once), lessThanOrEqualTo(kMaxBasenameBytes));
      }
    });

    test('drops NUL and control bytes (the invoice.pdf\\x00.exe trick)', () {
      expect(safeBasename('invoice.pdf\x00.exe'), 'invoice.pdf.exe');
    });

    test('collapses nested traversal tokens instead of leaving one behind', () {
      expect(safeBasename('....//....//etc'), 'etc');
    });

    test('empty, dot-only, or all-traversal names fall back', () {
      expect(safeBasename(''), 'received-file');
      expect(safeBasename('.'), 'received-file');
      expect(safeBasename('..'), 'received-file');
      expect(safeBasename('...'), 'received-file');
    });

    test('replaces characters Windows cannot store in a filename', () {
      expect(safeBasename('report<1>.txt'), 'report_1_.txt');
      expect(safeBasename('a"b'), 'a_b');
      expect(safeBasename('x|y'), 'x_y');
      // ':' 는 POSIX 구분자가 아니라 디렉토리 파트로는 안 잘리고 문자 자체가
      // 치환됨: ADS(Alternate Data Stream) 형태 이름 방어
      expect(safeBasename('file.txt:hidden'), 'file.txt_hidden');
    });

    test('trims trailing dots and spaces Explorer would silently drop', () {
      expect(safeBasename('name...'), 'name');
      expect(safeBasename('name   '), 'name');
      expect(safeBasename('name. . '), 'name');
    });

    test('prefixes Windows reserved device stems, case-insensitively', () {
      expect(safeBasename('CON'), '_CON');
      expect(safeBasename('con.txt'), '_con.txt');
      expect(safeBasename('Con.TXT'), '_Con.TXT');
      expect(safeBasename('COM1.txt'), '_COM1.txt');
      expect(safeBasename('nul.png'), '_nul.png');
      expect(safeBasename('LPT9'), '_LPT9');
      // 예약명과 우연히 같은 접두사인 평범한 이름은 안 건드림
      expect(safeBasename('console.txt'), 'console.txt');
    });

    // 첫 '.' 앞이 장치 이름이면 확장자가 여러 개여도·끝 공백이 있어도 장치로 열림
    test('catches device names with several extensions and new names', () {
      expect(safeBasename('NUL.tar.gz'), '_NUL.tar.gz');
      expect(safeBasename('con.tar.gz'), '_con.tar.gz');
      expect(safeBasename('CON .txt'), '_CON .txt');
      expect(safeBasename('COM0.txt'), '_COM0.txt');
      expect(safeBasename('LPT0'), '_LPT0');
      expect(safeBasename('COM¹.log'), '_COM¹.log');
      expect(safeBasename('CONIN\$'), '_CONIN\$');
      expect(safeBasename('conout\$.txt'), '_conout\$.txt');
      expect(safeBasename('nullable.tar.gz'), 'nullable.tar.gz');
    });

    // 길이 상한에서 자른 자리에 공백이 남으면 Windows가 지워서 'NUL'이 됨: 자른 뒤에 다듬고 검사
    test('a device name padded past the length limit still gets a prefix', () {
      expect(safeBasename('NUL${' ' * 300}x'), '_NUL');
      expect(safeBasename('report${' ' * 300}x'), 'report');
    });

    // 양방향 제어·폭 없는 문자로 확장자를 위장하지 못함
    test('drops bidi controls, zero-width and C1 characters', () {
      expect(safeBasename('invoice\u202Etxt.exe'), 'invoicetxt.exe');
      expect(safeBasename('a\u2066b\u2069c.pdf'), 'abc.pdf');
      expect(safeBasename('re\u200Bport.doc'), 'report.doc');
      expect(safeBasename('x\u0085y\u009F.txt'), 'xy.txt');
    });

    test('a leading dot does not make a hidden config file', () {
      expect(safeBasename('.bashrc'), '_.bashrc');
      expect(safeBasename('.ssh_config'), '_.ssh_config');
    });

    test('normalizes NFD Korean to a single NFC syllable', () {
      // '가' 완성형(U+AC00) vs L(ᄀ U+1100) + V(ᅡ U+1161) 분해형
      const composed = '가';
      const decomposed = '가';
      expect(safeBasename('$decomposed.txt'), '$composed.txt');
      expect(safeBasename('$decomposed.txt'), safeBasename('$composed.txt'));
    });

    test('leaves already-composed Korean and emoji names alone', () {
      expect(safeBasename('가.txt'), '가.txt');
      expect(safeBasename('🎉.txt'), '🎉.txt');
    });

    test('caps total UTF-8 bytes without splitting a Korean syllable', () {
      final longName = '가' * 200; // 3바이트 x 200 = 600바이트, 예산 훌쩍 초과
      final result = safeBasename('$longName.txt');
      expect(_utf8Length(result), lessThanOrEqualTo(kMaxBasenameBytes));
      // 잘린 자리가 서로게이트/멀티바이트 시퀀스 중간이 아니어야 함: 깨지면
      // 대체문자(U+FFFD) 없이도 runes 순회 자체가 예외를 던짐
      expect(() => result.runes.toList(), returnsNormally);
      expect(result.contains('�'), isFalse);
    });

    test('caps a pathologically long extension instead of throwing', () {
      final name = 'a.${'x' * 300}';
      expect(() => safeBasename(name), returnsNormally);
      final result = safeBasename(name);
      expect(_utf8Length(result), lessThanOrEqualTo(kMaxBasenameBytes));
      expect(p.extension(result).length, lessThanOrEqualTo(kMaxExtensionBytes));
    });
  });

  group('resolveWithin', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ig_path_safety_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('resolves a plain name inside the directory', () {
      final resolved = resolveWithin(dir.path, 'report.pdf');
      expect(resolved, p.join(p.normalize(p.absolute(dir.path)), 'report.pdf'));
    });

    test('a traversal-laden name still resolves inside the directory', () {
      // safeBasename가 이미 '../'를 지우지만, resolveWithin 자체도 독립
      // 레이어라: 이 조합이 어떤 입력으로도 디렉토리를 못 벗어남을 증명함
      final resolved = resolveWithin(dir.path, '../../../etc/passwd');
      expect(p.isWithin(p.normalize(p.absolute(dir.path)), resolved), isTrue);
    });
  });
}
