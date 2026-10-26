import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

part 'windows_clipboard/user32.dart';

// Windows 클립보드를 user32로 직접 다룸 (Flutter API엔 형식 지정이 없고, pasteboard 플러그인은 이미지를 %TEMP%에 BMP로 씀).
// 실패하면 false/null이라 호출부가 기본 경로로 감
abstract final class WindowsClipboard {
  static const int _cfBitmap = 2;
  static const int _cfDib = 8;
  static const int _cfUnicodeText = 13;
  static const int _cfHdrop = 15;
  static const int _cfDibV5 = 17;
  static const int _gmemMoveable = 0x0002;

  // 이 형식이 하나라도 있으면 Win+V 기록·클라우드 동기화에서 빠짐 (Microsoft 문서의 고정 이름)
  static const List<String> _privateFormats = [
    'ExcludeClipboardContentFromMonitorProcessing',
    'CanIncludeInClipboardHistory',
    'CanUploadToCloudClipboard',
  ];

  // 우리가 쓴 직후의 시퀀스 번호: 내용을 안 읽고 아직 우리 사본인지 비교함
  static int? _sequence;

  // 테스트에서 CloseClipboard 때 번호가 바뀌는 Windows 동작을 흉내 낸 모형으로 교체함
  @visibleForTesting
  static User32 Function() user32Override = User32.new;

  static bool setPrivateText(String text) {
    _sequence = null;
    try {
      final api = user32Override();
      final owner = api.ownerWindow();
      if (owner == 0 || api.openClipboard(owner) == 0) return false;
      var ok = false;
      try {
        ok =
            api.emptyClipboard() != 0 && api.put(_cfUnicodeText, _utf16z(text));
        // 기록·동기화 제외 값은 DWORD 0
        for (final name in _privateFormats) {
          if (!ok) break;
          final format = api.register(name);
          ok = format != 0 && api.put(format, Uint8List(4));
        }
        if (!ok) api.emptyClipboard();
      } finally {
        api.closeClipboard();
      }
      // CloseClipboard가 CF_LOCALE 등을 합성하며 번호를 올려서 닫은 뒤에 읽음. 그 사이 다른 앱이 복사했으면
      // 소유 창이 바뀌므로, 번호를 읽은 뒤에도 우리 창이 주인일 때만 우리 사본으로 침
      if (ok) {
        final sequence = api.sequence();
        if (api.clipboardOwner() == owner) _sequence = sequence;
      }
      return ok;
    } on Object {
      return false;
    }
  }

  static void clearIfOwn() {
    final sequence = _sequence;
    _sequence = null;
    if (sequence == null) return;
    try {
      final api = user32Override();
      final owner = api.ownerWindow();
      if (owner == 0 || api.openClipboard(owner) == 0) return;
      try {
        // 열어 둔 동안은 다른 앱이 못 바꿈: 주인과 번호가 둘 다 그대로일 때만 비움
        if (api.clipboardOwner() == owner && api.sequence() == sequence) {
          api.emptyClipboard();
        }
      } finally {
        api.closeClipboard();
      }
    } on Object {
      // 확인하지 못하면 다른 앱의 내용일 수 있어 건드리지 않음
    }
  }

  // 붙여넣기 버튼 표시용: 형식이 있는지만 봄 (내용을 열지 않음)
  static ({bool image, bool files})? kinds() {
    try {
      final api = user32Override();
      return (
        image: [_cfDib, _cfDibV5, _cfBitmap].any((f) => api.available(f)),
        files: api.available(_cfHdrop),
      );
    } on Object {
      return null;
    }
  }

  // 클립보드 이미지를 메모리에서 바로 .bmp 바이트로 읽음 (임시 파일 없음). CF_DIB는 다른 비트맵 형식에서도 OS가 합성해 줌
  static Uint8List? readImage() {
    try {
      final api = user32Override();
      if (!api.available(_cfDib) || api.openClipboard(api.ownerWindow()) == 0) {
        return null;
      }
      try {
        final handle = api.getData(_cfDib);
        final size = handle == 0 ? 0 : api.globalSize(handle);
        final data = size == 0 ? nullptr : api.globalLock(handle);
        if (data == nullptr) return null;
        try {
          return dibToBmp(Uint8List.fromList(data.asTypedList(size)));
        } finally {
          api.globalUnlock(handle);
        }
      } finally {
        api.closeClipboard();
      }
    } on Object {
      return null;
    }
  }

  static Uint8List _utf16z(String text) {
    final bytes = Uint8List((text.length + 1) * 2);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < text.length; i++) {
      view.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
    }
    return bytes;
  }
}

// CF_DIB에 14바이트 파일 머리를 붙여 .bmp로 만듦. 픽셀 시작 = 14 + 머리 + 색표(8비트 이하면 2^bit개, 아니면 biClrUsed개)
// + 40바이트 머리의 BI_BITFIELDS 마스크
Uint8List? dibToBmp(Uint8List dib) {
  if (dib.length < 40) return null;
  final info = ByteData.sublistView(dib);
  final headerSize = info.getUint32(0, Endian.little);
  if (headerSize < 40 || headerSize > dib.length) return null;
  final bitCount = info.getUint16(14, Endian.little);
  final compression = info.getUint32(16, Endian.little);
  final colorsUsed = info.getUint32(32, Endian.little);
  final palette = bitCount <= 8 && colorsUsed == 0 ? 1 << bitCount : colorsUsed;
  final masks = headerSize == 40
      ? switch (compression) {
          3 => 12, // BI_BITFIELDS
          6 => 16, // BI_ALPHABITFIELDS
          _ => 0,
        }
      : 0;
  final pixels = 14 + headerSize + palette * 4 + masks;
  if (pixels > 14 + dib.length) return null;
  final bmp = Uint8List(14 + dib.length)..setRange(14, 14 + dib.length, dib);
  ByteData.sublistView(bmp)
    ..setUint8(0, 0x42) // 'B'
    ..setUint8(1, 0x4D) // 'M'
    ..setUint32(2, bmp.length, Endian.little)
    ..setUint32(10, pixels, Endian.little);
  return bmp;
}
