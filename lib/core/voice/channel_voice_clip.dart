import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'voice_clip.dart';
import 'voice_wav.dart';

// iOS·macOS(AVAudioPlayer(data:))와 Android(MediaPlayer + 메모리 MediaDataSource) 네이티브 재생기.
// WAV 바이트는 네이티브 메모리에만 있고 dispose 때 놓음
class ChannelVoiceClip extends PolledVoiceClip {
  ChannelVoiceClip._(this._id, super.duration);

  static const MethodChannel _channel = MethodChannel('intragram/voice');
  static final Map<String, ChannelVoiceClip> _live = {};
  static var _nextId = 0;
  static var _listening = false;

  final String _id;

  static Future<VoiceClip> load(PcmWav wav) async {
    _listen();
    final id = 'v${_nextId++}';
    final bytes = _wavBytes(wav);
    final int? millis;
    try {
      millis = await _channel.invokeMethod<int>('load', <String, Object>{
        'id': id,
        'bytes': bytes,
      });
    } finally {
      // 채널이 보낼 때 복사해 감. 넘기려고 만든 평문 사본은 바로 지움
      bytes.fillRange(0, bytes.length, 0);
    }
    if (millis == null) throw StateError('voice player did not load');
    final clip = ChannelVoiceClip._(id, wav.duration);
    _live[id] = clip;
    return clip;
  }

  // 네이티브가 끝났다고 알려 줌 (completed, 인자는 id)
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'completed') _live[call.arguments]?.markCompleted();
    });
  }

  Future<T?> _call<T>(String method, [Map<String, Object>? extra]) =>
      _channel.invokeMethod<T>(method, <String, Object>{'id': _id, ...?extra});

  @override
  Future<void> startOutput({required bool rewind}) =>
      _call<void>('play', {'rewind': rewind});

  @override
  Future<void> pauseOutput() => _call<void>('pause');

  @override
  Future<Duration> outputPosition() async =>
      Duration(milliseconds: await _call<int>('position') ?? 0);

  @override
  Future<bool> outputFinished() async => false;

  @override
  Future<void> releaseOutput() async {
    _live.remove(_id);
    await _call<void>('dispose');
  }
}

// 검사 통과한 표준 44바이트 머리로 다시 감싸서 원본의 다른 청크(LIST 등)가 디코더에 안 닿게 함
Uint8List _wavBytes(PcmWav wav) {
  final pcm = wav.pcm;
  final out = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(out, 0, 44)
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, wav.channels, Endian.little)
    ..setUint32(24, wav.sampleRate, Endian.little)
    ..setUint32(28, wav.byteRate, Endian.little)
    ..setUint16(32, wav.channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, pcm.length, Endian.little);
  const tags = {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'};
  tags.forEach((at, tag) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(at + i, tag.codeUnitAt(i));
    }
  });
  out.setRange(44, out.length, pcm);
  return out;
}
