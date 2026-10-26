part of '../windows_clipboard.dart';

// Win32: BOOL=Int32, HANDLE·HGLOBAL·HWND=IntPtr, SIZE_T=UintPtr, UINT=Uint32 (x64·ARM64)
typedef _Bool0 = Int32 Function();
typedef _Handle0 = IntPtr Function();
typedef _Bool0Dart = int Function();
typedef _BoolOf = Int32 Function(IntPtr);
typedef _BoolOfFormat = Int32 Function(Uint32);
typedef _OfInt = int Function(int);
typedef _HandleOf = IntPtr Function(IntPtr);
typedef _HandleOfFormat = IntPtr Function(Uint32);
typedef _HandleOf2 = IntPtr Function(Uint32, IntPtr);
typedef _Alloc = IntPtr Function(Uint32, UintPtr);
typedef _SizeOf = UintPtr Function(IntPtr);
typedef _OfInt2 = int Function(int, int);
typedef _OfName = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _OfNameDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

// 쓰는 user32·kernel32 함수만 묶음. 소유 창은 Flutter 러너 창 (hwnd 없이 열면 SetClipboardData가 실패함).
// 테스트는 Windows 클립보드 동작을 흉내 낸 모형으로 바꿔 끼움
class User32 {
  User32()
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

  int clipboardOwner() =>
      _user32.lookupFunction<_Handle0, _Bool0Dart>('GetClipboardOwner')();

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
      _kernel32.lookupFunction<_SizeOf, _OfInt>('GlobalSize')(handle);

  Pointer<Uint8> globalLock(int handle) =>
      _kernel32.lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('GlobalLock')(handle);

  void globalUnlock(int handle) =>
      _kernel32.lookupFunction<_BoolOf, _OfInt>('GlobalUnlock')(handle);

  // 성공하면 메모리는 시스템 것이 됨. 실패하면 직접 풂
  bool put(int format, Uint8List bytes) {
    final handle = _kernel32.lookupFunction<_Alloc, _OfInt2>('GlobalAlloc')(
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
