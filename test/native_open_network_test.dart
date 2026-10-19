import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/native_open.dart';

// 받은 파일 중 열면 OS 앱이 인터넷에 닿는 형식(웹 페이지, 바로 가기, 원격 데스크톱, 재생 목록, 원격 설치기)은
// 열기 전에 묻게 함. 실행 파일 목록과는 따로 둠
void main() {
  test('web pages, shortcuts and remote launchers reach the network', () {
    for (final name in [
      'page.html',
      'page.HTM',
      'pic.svg',
      'archive.mht',
      'link.url',
      'link.webloc',
      'remote.rdp',
      'list.m3u8',
      'app.jnlp',
      'setup.appinstaller',
      'lib.library-ms',
    ]) {
      expect(NativeOpen.reachesNetwork(name), isTrue, reason: name);
    }
  });

  test('ordinary documents do not', () {
    for (final name in ['report.pdf', 'photo.jpg', 'notes.txt', 'a.zip']) {
      expect(NativeOpen.reachesNetwork(name), isFalse, reason: name);
    }
  });

  test('a .terminal file counts as a program', () {
    expect(NativeOpen.isExecutable('session.terminal'), isTrue);
  });
}
