import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:intragram/core/native_open.dart';

void main() {
  group('NativeOpen.open on Windows', () {
    late Directory dir;
    late Future<bool> Function(Uri uri, {required LaunchMode mode})
    previousOverride;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ig_native_open_');
      previousOverride = NativeOpen.launchUrlOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() {
      NativeOpen.launchUrlOverride = previousOverride;
      debugDefaultTargetPlatformOverride = null;
      dir.deleteSync(recursive: true);
    });

    test('passes a shell-metacharacter filename only as a Uri, never a shell '
        'string', () async {
      final path = p.join(dir.path, 'a & b ^ (c).txt');
      File(path).writeAsStringSync('x');

      Uri? capturedUri;
      LaunchMode? capturedMode;
      NativeOpen.launchUrlOverride = (uri, {required mode}) async {
        capturedUri = uri;
        capturedMode = mode;
        return true;
      };

      final ok = await NativeOpen.open(path);

      expect(ok, isTrue);
      expect(capturedMode, LaunchMode.externalApplication);
      // Uri 값끼리 비교함: POSIX 테스트 호스트에서 만든 경로를 Windows 모드로 왕복 변환한 문자열은 구분자 표현이 달라서 원본 문자열과 안 맞음.
      // 핵심은 셸 메타문자가 이스케이프나 셸 재해석 없이 Uri에 그대로 실렸는지라 Uri 동등성이 정확한 증거
      expect(capturedUri, Uri.file(path, windows: true));
    });

    test('returns false without launching when the file is gone', () async {
      final path = p.join(dir.path, 'missing.txt');
      var launched = false;
      NativeOpen.launchUrlOverride = (uri, {required mode}) async {
        launched = true;
        return true;
      };

      final ok = await NativeOpen.open(path);

      expect(ok, isFalse);
      expect(launched, isFalse);
    });
  });

  // macOS: 자식 /usr/bin/open 대신 프로세스 안 NSWorkspace(url_launcher)로 엶
  test('macOS opens a received file in process, not through open(1)', () async {
    final dir = Directory.systemTemp.createTempSync('ig_native_open_mac_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final previous = NativeOpen.launchUrlOverride;
    addTearDown(() => NativeOpen.launchUrlOverride = previous);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final path = p.join(dir.path, 'notes.txt');
    File(path).writeAsStringSync('x');
    Uri? captured;
    NativeOpen.launchUrlOverride = (uri, {required mode}) async {
      captured = uri;
      return true;
    };

    expect(await NativeOpen.open(path), isTrue);
    expect(captured, Uri.file(path));
  });

  test('isExecutable flags runnable files regardless of case', () {
    for (final name in [
      'setup.EXE',
      'run.bat',
      'x.ps1',
      'a.sh',
      'App.AppImage',
    ]) {
      expect(NativeOpen.isExecutable('/tmp/$name'), isTrue, reason: name);
    }
    for (final name in ['photo.jpg', 'notes.txt', 'archive.zip', 'noext']) {
      expect(NativeOpen.isExecutable('/tmp/$name'), isFalse, reason: name);
    }
  });
}
