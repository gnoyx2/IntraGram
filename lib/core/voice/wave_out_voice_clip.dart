import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'voice_clip.dart';
import 'voice_wav.dart';

// Windows: winmm waveOut에 네이티브 메모리 PCM 버퍼를 그대로 넘김 (파일·캐시 없음). 콜백 없이 헤더의 WHDR_DONE을 폴링해서 끝을 앎
class WaveOutVoiceClip extends PolledVoiceClip {
  WaveOutVoiceClip._(
    this._api,
    this._device,
    this._buffer,
    this._header,
    this._byteRate,
    super.duration,
  );

  static Future<VoiceClip> load(PcmWav wav) async {
    final api = _WinMm();
    final format = calloc<_WaveFormatEx>();
    final handle = calloc<IntPtr>();
    try {
      format.ref
        ..wFormatTag =
            1 // WAVE_FORMAT_PCM
        ..nChannels = wav.channels
        ..nSamplesPerSec = wav.sampleRate
        ..nAvgBytesPerSec = wav.byteRate
        ..nBlockAlign = wav.channels * 2
        ..wBitsPerSample = 16
        ..cbSize = 0;
      final rc = api.open(handle, _waveMapper, format, 0, 0, 0);
      if (rc != 0) throw StateError('waveOutOpen failed: $rc');
      final pcm = wav.pcm;
      final buffer = calloc<Uint8>(pcm.length);
      buffer.asTypedList(pcm.length).setAll(0, pcm);
      final header = calloc<_WaveHdr>();
      header.ref
        ..lpData = buffer
        ..dwBufferLength = pcm.length;
      return WaveOutVoiceClip._(
        api,
        handle.value,
        buffer,
        header,
        wav.byteRate,
        wav.duration,
      );
    } finally {
      calloc
        ..free(format)
        ..free(handle);
    }
  }

  static const int _waveMapper = 0xFFFFFFFF;
  static const int _whdrDone = 0x1;
  static const int _timeBytes = 0x4;

  final _WinMm _api;
  final int _device;
  final Pointer<Uint8> _buffer;
  final Pointer<_WaveHdr> _header;
  final int _byteRate;
  var _queued = false;

  @override
  Future<void> startOutput({required bool rewind}) async {
    if (_queued && !rewind) {
      _api.restart(_device);
      return;
    }
    if (_queued) {
      _api.reset(_device);
      _api.unprepare(_device, _header, sizeOf<_WaveHdr>());
      _queued = false;
    }
    _header.ref.dwFlags = 0;
    // 실패를 삼키면 WHDR_DONE이 영영 안 서서 계속 '재생 중'으로 남음 (장치가 빠진 경우 등)
    final prepared = _api.prepare(_device, _header, sizeOf<_WaveHdr>());
    if (prepared != 0) {
      throw StateError('waveOutPrepareHeader failed: $prepared');
    }
    final written = _api.write(_device, _header, sizeOf<_WaveHdr>());
    if (written != 0) {
      _api.unprepare(_device, _header, sizeOf<_WaveHdr>());
      throw StateError('waveOutWrite failed: $written');
    }
    _queued = true;
  }

  @override
  Future<void> pauseOutput() async => _api.pause(_device);

  @override
  Future<Duration> outputPosition() async {
    final time = calloc<_MmTime>()..ref.wType = _timeBytes;
    try {
      _api.position(_device, time, sizeOf<_MmTime>());
      return Duration(
        microseconds: time.ref.cb * Duration.microsecondsPerSecond ~/ _byteRate,
      );
    } finally {
      calloc.free(time);
    }
  }

  @override
  Future<bool> outputFinished() async =>
      _queued && (_header.ref.dwFlags & _whdrDone) != 0;

  @override
  Future<void> releaseOutput() async {
    _api.reset(_device);
    if (_queued) _api.unprepare(_device, _header, sizeOf<_WaveHdr>());
    _api.close(_device);
    final length = _header.ref.dwBufferLength;
    _buffer.asTypedList(length).fillRange(0, length, 0);
    calloc
      ..free(_buffer)
      ..free(_header);
  }
}

// mmsystem.h가 바이트 정렬(pshpack1)이라 WAVEFORMATEX(18바이트)·MMTIME(12바이트)은 packed
@Packed(1)
final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

final class _WaveHdr extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<_WaveHdr> lpNext;
  @IntPtr()
  external int reserved;
}

@Packed(1)
final class _MmTime extends Struct {
  @Uint32()
  external int wType;
  // union u의 첫 4바이트 (TIME_BYTES면 cb)
  @Uint32()
  external int cb;
  @Uint32()
  external int unionTail;
}

typedef _OpenNative =
    Uint32 Function(
      Pointer<IntPtr>,
      Uint32,
      Pointer<_WaveFormatEx>,
      IntPtr,
      IntPtr,
      Uint32,
    );
typedef _OpenDart =
    int Function(Pointer<IntPtr>, int, Pointer<_WaveFormatEx>, int, int, int);
typedef _HandleOp = Uint32 Function(IntPtr device);
typedef _HandleOpDart = int Function(int device);
typedef _HeaderOp =
    Uint32 Function(IntPtr device, Pointer<_WaveHdr> header, Uint32 size);
typedef _HeaderOpDart =
    int Function(int device, Pointer<_WaveHdr> header, int size);
typedef _PositionOp =
    Uint32 Function(IntPtr device, Pointer<_MmTime> time, Uint32 size);
typedef _PositionOpDart =
    int Function(int device, Pointer<_MmTime> time, int size);

// Windows에서만 만들어짐 (다른 플랫폼에선 winmm.dll을 열지 않음)
class _WinMm {
  _WinMm() : _lib = DynamicLibrary.open('winmm.dll');

  final DynamicLibrary _lib;

  late final open = _lib.lookupFunction<_OpenNative, _OpenDart>('waveOutOpen');
  late final prepare = _header('waveOutPrepareHeader');
  late final unprepare = _header('waveOutUnprepareHeader');
  late final write = _header('waveOutWrite');
  late final pause = _handle('waveOutPause');
  late final restart = _handle('waveOutRestart');
  late final reset = _handle('waveOutReset');
  late final close = _handle('waveOutClose');
  late final position = _lib.lookupFunction<_PositionOp, _PositionOpDart>(
    'waveOutGetPosition',
  );

  _HeaderOpDart _header(String name) =>
      _lib.lookupFunction<_HeaderOp, _HeaderOpDart>(name);
  _HandleOpDart _handle(String name) =>
      _lib.lookupFunction<_HandleOp, _HandleOpDart>(name);
}
