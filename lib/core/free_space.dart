import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// path가 있는 볼륨에서 이 앱이 쓸 수 있는 남은 바이트. dart:io엔 이 API가 없어 OS에 직접 물음
// 모르는 플랫폼·32비트 빌드·호출 실패면 null (호출부는 확인 없이 진행)
// iOS는 statvfs가 정리 가능한(purgeable) 공간을 빼고 보여서 실제로 받을 수 있는 파일도 막을 수 있어 묻지 않음
int? freeBytesAt(String path) {
  try {
    if (Platform.isWindows) return _windowsFree(path);
    if (sizeOf<IntPtr>() != 8) return null;
    if (Platform.isMacOS) return _statvfsFree(DynamicLibrary.process(), path);
    if (Platform.isLinux) return _statvfsFree(DynamicLibrary.process(), path);
    if (Platform.isAndroid) {
      return _statvfsFree(DynamicLibrary.open('libc.so'), path);
    }
  } on Object {
    return null;
  }
  return null;
}

typedef _StatvfsC = Int32 Function(Pointer<Utf8> path, Pointer<Uint8> out);
typedef _StatvfsDart = int Function(Pointer<Utf8> path, Pointer<Uint8> out);

// struct statvfs (64비트): f_bsize, f_frsize(오프셋 8, 8바이트) 다음 블록 수들.
// Darwin은 fsblkcnt_t가 32비트라 f_bavail이 오프셋 24(4바이트), glibc·bionic은 오프셋 32(8바이트)
const int _statvfsBufferBytes = 256;

int? _statvfsFree(DynamicLibrary libc, String path) {
  final statvfs = libc.lookupFunction<_StatvfsC, _StatvfsDart>('statvfs');
  final nativePath = path.toNativeUtf8();
  final out = calloc<Uint8>(_statvfsBufferBytes);
  try {
    if (statvfs(nativePath, out) != 0) return null;
    final view = ByteData.sublistView(out.asTypedList(_statvfsBufferBytes));
    final fragment = view.getUint64(8, Endian.host);
    final available = Platform.isMacOS
        ? view.getUint32(24, Endian.host)
        : view.getUint64(32, Endian.host);
    return fragment * available;
  } finally {
    calloc.free(nativePath);
    calloc.free(out);
  }
}

typedef _FreeSpaceC =
    Int32 Function(
      Pointer<Utf16> directory,
      Pointer<Uint64> availableToCaller,
      Pointer<Uint64> total,
      Pointer<Uint64> totalFree,
    );
typedef _FreeSpaceDart =
    int Function(
      Pointer<Utf16> directory,
      Pointer<Uint64> availableToCaller,
      Pointer<Uint64> total,
      Pointer<Uint64> totalFree,
    );

int? _windowsFree(String path) {
  final getFree = DynamicLibrary.open(
    'kernel32.dll',
  ).lookupFunction<_FreeSpaceC, _FreeSpaceDart>('GetDiskFreeSpaceExW');
  final nativePath = path.toNativeUtf16();
  final available = calloc<Uint64>();
  try {
    if (getFree(nativePath, available, nullptr, nullptr) == 0) return null;
    return available.value;
  } finally {
    calloc.free(nativePath);
    calloc.free(available);
  }
}
