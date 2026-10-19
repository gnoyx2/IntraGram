import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Windows 클립보드를 user32로 직접 다룸 (Flutter 기본 API엔 형식 지정이 없고, pasteboard 플러그인은
// 이미지를 %TEMP%에 BMP 파일로 써서 넘김). 실패하면 false/null을 돌려 호출부가 기본 경로로 감
abstract final class WindowsClipboard {
  static const int _cfBitmap = 2;
  static const int _cfDib = 8;
  static const int _cfUnicodeText = 13;
  static const int _cfHdrop = 15;
  static const int _cfDibV5 = 17;
  static const int _gmemMoveable = 0x0002;

  // 이 형식이 하나라도 있으면 Win+V 기록과 클라우드 클립보드 동기화에서 빠짐 (Microsoft 문서의 고정 이름)
  static const List<String> _privateFormats = [
    'ExcludeClipboardContentFromMonitorProcessing',
    'CanIncludeInClipboardHistory',
    'CanUploadToCloudClipboard',
  ];

  // 마지막으로 우리가 쓴 직후의 시퀀스 번호: 내용을 안 읽고 아직 우리 복사본인지 비교함
  static int? _sequence;

  static bool setPrivateText(String text) {
    try {
      final api = _User32();
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
      _sequence = ok ? api.sequence() : null;
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
      final api = _User32();
      if (api.sequence() != sequence) return;
      final owner = api.ownerWindow();
      if (owner == 0 || api.openClipboard(owner) == 0) return;
      try {
        api.emptyClipboard();
      } finally {
        api.closeClipboard();
      }
    } on Object {
      // 확인 못 하면 남의 내용일 수 있어 건드리지 않음
    }
  }

  // 붙여넣기 버튼 표시용: 형식이 있는지만 봄 (내용을 열지 않음)
  static ({bool image, bool files})? kinds() {
    try {
      final api = _User32();
      return (
        image: [_cfDib, _cfDibV5, _cfBitmap].any((f) => api.available(f)),
        files: api.available(_cfHdrop),
      );
    } on Object {
      return null;
    }
  }

  // 클립보드 이미지를 메모리에서 바로 .bmp 바이트로 (임시 파일 없음). CF_DIB는 OS가 다른 비트맵 형식에서도 만들어 줌
  static Uint8List? readImage() {
    try {
      final api = _User32();
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

// CF_DIB(BITMAPINFOHEADER + 색표 + 픽셀)에 14바이트 파일 머리를 붙여 .bmp로 만듦. 픽셀 시작 =
// 14 + 머리 크기 + 색표(8비트 이하는 2^bit개, 아니면 biClrUsed개) + 40바이트 머리의 BI_BITFIELDS 마스크
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

// Win32 시그니처: BOOL은 Int32, HANDLE·HGLOBAL·HWND·SIZE_T는 IntPtr, UINT는 Uint32
typedef _Bool0 = Int32 Function();
typedef _Bool0Dart = int Function();
typedef _BoolOf = Int32 Function(IntPtr);
typedef _BoolOfFormat = Int32 Function(Uint32);
typedef _OfInt = int Function(int);
typedef _HandleOf = IntPtr Function(IntPtr);
typedef _HandleOfFormat = IntPtr Function(Uint32);
typedef _HandleOf2 = IntPtr Function(Uint32, IntPtr);
typedef _OfInt2 = int Function(int, int);
typedef _OfName = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _OfNameDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

// 쓰는 user32·kernel32 함수만 묶음. 소유 창은 Flutter 러너 창 (hwnd 없이 열면 SetClipboardData가 실패함)
final class _User32 {
  _User32()
    : _user32 = DynamicLibrary.open('user32.dll'),
      _kernel32 = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _user32;
  final DynamicLibrary _kernel32;

  int ownerWindow() {
    final find = _user32.lookupFunction<_OfName, _OfNameDart>('FindWindowW');
    final name = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    try {
      return find(name, nullptr);
    } finally {
      calloc.free(name);
    }
  }

  int openClipboard(int owner) =>
      _user32.lookupFunction<_BoolOf, _OfInt>('OpenClipboard')(owner);

  int closeClipboard() =>
      _user32.lookupFunction<_Bool0, _Bool0Dart>('CloseClipboard')();

  int emptyClipboard() =>
      _user32.lookupFunction<_Bool0, _Bool0Dart>('EmptyClipboard')();

  int sequence() => _user32.lookupFunction<Uint32 Function(), _Bool0Dart>(
    'GetClipboardSequenceNumber',
  )();

  bool available(int format) =>
      _user32.lookupFunction<_BoolOfFormat, _OfInt>(
        'IsClipboardFormatAvailable',
      )(format) !=
      0;

  int getData(int format) => _user32.lookupFunction<_HandleOfFormat, _OfInt>(
    'GetClipboardData',
  )(format);

  int register(String name) {
    final native = name.toNativeUtf16();
    try {
      return _user32.lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('RegisterClipboardFormatW')(native);
    } finally {
      calloc.free(native);
    }
  }

  int globalSize(int handle) =>
      _kernel32.lookupFunction<_HandleOf, _OfInt>('GlobalSize')(handle);

  Pointer<Uint8> globalLock(int handle) =>
      _kernel32.lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('GlobalLock')(handle);

  void globalUnlock(int handle) =>
      _kernel32.lookupFunction<_BoolOf, _OfInt>('GlobalUnlock')(handle);

  // 성공하면 메모리는 시스템 것이 됨. 실패하면 직접 풂
  bool put(int format, Uint8List bytes) {
    final handle = _kernel32.lookupFunction<_HandleOf2, _OfInt2>('GlobalAlloc')(
      WindowsClipboard._gmemMoveable,
      bytes.length,
    );
    if (handle == 0) return false;
    final data = globalLock(handle);
    if (data != nullptr) {
      data.asTypedList(bytes.length).setAll(0, bytes);
      globalUnlock(handle);
      final set = _user32.lookupFunction<_HandleOf2, _OfInt2>(
        'SetClipboardData',
      );
      if (set(format, handle) != 0) return true;
    }
    _kernel32.lookupFunction<_HandleOf, _OfInt>('GlobalFree')(handle);
    return false;
  }
}
