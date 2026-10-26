import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/windows_clipboard.dart';

// Windows 클립보드 모형. EmptyClipboard·SetClipboardData가 번호를 올리고, 바뀐 채로 닫으면
// CloseClipboard가 CF_LOCALE 등을 합성하며 번호를 또 올림 (Wine dlls/user32/tests/clipboard.c가 실제
// Windows에서 단정하는 check_messages(win, 2, …)). 구현은 증가량을 몰라야 함
class _Clipboard implements User32 {
  static const ours = 0x100;
  static const theirs = 0x200;
  static const unicodeText = 13;

  int seq = 40;
  int owner = 0;
  int? openBy;
  int _openedAt = 0;
  int opens = 0;
  final formats = <int, Uint8List>{};
  final registered = <String>[];
  bool openFails = false;
  bool putFails = false;
  // 우리 CloseClipboard가 끝난 바로 뒤, 다음 API 호출 전에 끼어드는 다른 앱
  void Function()? afterClose;

  @override
  int ownerWindow() => ours;

  @override
  int openClipboard(int window) {
    if (openFails || openBy != null) return 0;
    opens++;
    openBy = window;
    _openedAt = seq;
    return 1;
  }

  @override
  int emptyClipboard() {
    formats.clear();
    owner = openBy!;
    seq++;
    return 1;
  }

  @override
  bool put(int format, Uint8List bytes) {
    if (putFails) return false;
    formats[format] = bytes;
    seq++;
    return true;
  }

  @override
  int closeClipboard() {
    openBy = null;
    if (seq != _openedAt && formats.containsKey(unicodeText)) seq += 2;
    final intruder = afterClose;
    afterClose = null;
    intruder?.call();
    return 1;
  }

  @override
  int sequence() => seq;

  @override
  int clipboardOwner() => owner;

  @override
  int register(String name) {
    registered.add(name);
    return 0xC000 + registered.length;
  }

  void copyElsewhere(String value) {
    expect(openClipboard(theirs), 1);
    emptyClipboard();
    final units = Uint16List.fromList([...value.codeUnits, 0]);
    put(unicodeText, units.buffer.asUint8List());
    closeClipboard();
  }

  String? get text {
    final bytes = formats[unicodeText];
    if (bytes == null) return null;
    final units = Uint16List.sublistView(bytes);
    return String.fromCharCodes(units.takeWhile((unit) => unit != 0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Clipboard clipboard;
  setUp(() {
    clipboard = _Clipboard();
    WindowsClipboard.user32Override = () => clipboard;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    WindowsClipboard.user32Override = User32.new;
    debugDefaultTargetPlatformOverride = null;
  });

  test('a private copy is cleared 60 s later although CloseClipboard '
      'bumps the sequence', () {
    fakeAsync((async) {
      OsPrivacy.copySensitive('secret');
      expect(clipboard.text, 'secret');
      async.elapse(OsPrivacy.clipboardLifetime - const Duration(seconds: 1));
      expect(clipboard.text, 'secret');
      async.elapse(const Duration(seconds: 1));
      expect(clipboard.formats, isEmpty);
      expect(clipboard.openBy, isNull);
    });
  });

  test('history and cloud exclusion formats ride along with the text', () {
    expect(WindowsClipboard.setPrivateText('한글 secret'), isTrue);
    expect(clipboard.registered, [
      'ExcludeClipboardContentFromMonitorProcessing',
      'CanIncludeInClipboardHistory',
      'CanUploadToCloudClipboard',
    ]);
    for (var format = 0xC001; format <= 0xC003; format++) {
      expect(clipboard.formats[format], Uint8List(4));
    }
    expect(clipboard.text, '한글 secret');
  });

  for (final value in ['copied elsewhere', 'secret']) {
    test('a copy by another app before expiry stays ($value)', () {
      fakeAsync((async) {
        OsPrivacy.copySensitive('secret');
        async.elapse(const Duration(seconds: 30));
        clipboard.copyElsewhere(value);
        async.elapse(const Duration(seconds: 31));
        expect(clipboard.text, value);
        expect(clipboard.owner, _Clipboard.theirs);
      });
    });
  }

  test('a copy that lands between CloseClipboard and the sequence read '
      'is not claimed', () {
    clipboard.afterClose = () => clipboard.copyElsewhere('secret');
    expect(WindowsClipboard.setPrivateText('secret'), isTrue);
    WindowsClipboard.clearIfOwn();
    expect(clipboard.text, 'secret');
    expect(clipboard.owner, _Clipboard.theirs);
  });

  test('the earlier timer does not clear a newer private copy', () {
    fakeAsync((async) {
      OsPrivacy.copySensitive('first');
      async.elapse(const Duration(seconds: 40));
      OsPrivacy.copySensitive('second');
      async.elapse(const Duration(seconds: 21));
      expect(clipboard.text, 'second');
      async.elapse(const Duration(seconds: 39));
      expect(clipboard.formats, isEmpty);
    });
  });

  test('open or write failures leave other clipboard contents alone', () {
    clipboard.copyElsewhere('existing');
    clipboard.openFails = true;
    expect(WindowsClipboard.setPrivateText('secret'), isFalse);
    expect(clipboard.text, 'existing');
    clipboard.openFails = false;
    WindowsClipboard.clearIfOwn();
    expect(clipboard.text, 'existing');

    clipboard.putFails = true;
    expect(WindowsClipboard.setPrivateText('secret'), isFalse);
    expect(clipboard.openBy, isNull);
    clipboard.putFails = false;
    clipboard.copyElsewhere('later');
    WindowsClipboard.clearIfOwn();
    expect(clipboard.text, 'later');
  });

  test('panic cancels the pending expiry check', () {
    const privacy = MethodChannel('intragram/privacy');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(privacy, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(privacy, null));
    fakeAsync((async) {
      OsPrivacy.copySensitive('secret');
      final opens = clipboard.opens;
      OsPrivacy.clearClipboard();
      async.elapse(OsPrivacy.clipboardLifetime * 2);
      expect(clipboard.opens, opens);
    });
  });
}
