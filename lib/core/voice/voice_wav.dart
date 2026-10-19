import 'dart:math' as math;
import 'dart:typed_data';

// 음성 메시지의 유일한 형식(녹음기가 만드는 16비트 PCM WAV)을 읽은 결과
class PcmWav {
  const PcmWav({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  // data 청크 (2바이트 샘플이 덜 찬 꼬리는 버림)
  final ByteData samples;
  final int sampleRate;
  final int channels;

  int get byteRate => sampleRate * channels * 2;

  Duration get duration =>
      Duration(microseconds: samples.lengthInBytes * 1000000 ~/ byteRate);

  Uint8List get pcm => Uint8List.sublistView(samples);
}

// 상대가 보낸 바이트라 RIFF 청크를 끝까지 방어적으로 따라감. 정상 범위(8~48 kHz, 1~2채널,
// 16비트 PCM)가 아니면 null이라, 재생기에는 이 형식만 넘어감 (다른 컨테이너·재생목록으로 해석될 여지 없음)
PcmWav? parsePcm16Wav(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final view = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  int? sampleRate;
  int? channels;
  var at = 12;
  while (at + 8 <= bytes.length) {
    final size = view.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (tag(at) == 'fmt ' && body + 16 <= bytes.length) {
      final format = _fmtOf(view, body);
      sampleRate = format?.sampleRate;
      channels = format?.channels;
    } else if (tag(at) == 'data') {
      if (sampleRate == null || channels == null) return null;
      final end = math.min(bytes.length, body + size);
      final usable = end - body - (end - body) % (2 * channels);
      return PcmWav(
        samples: ByteData.sublistView(bytes, body, body + usable),
        sampleRate: sampleRate,
        channels: channels,
      );
    }
    at = body + size + size % 2;
  }
  return null;
}

({int sampleRate, int channels})? _fmtOf(ByteData view, int body) {
  final format = view.getUint16(body, Endian.little);
  final channels = view.getUint16(body + 2, Endian.little);
  final sampleRate = view.getUint32(body + 4, Endian.little);
  final byteRate = view.getUint32(body + 8, Endian.little);
  final blockAlign = view.getUint16(body + 12, Endian.little);
  final bits = view.getUint16(body + 14, Endian.little);
  final ok =
      format == 1 &&
      bits == 16 &&
      channels >= 1 &&
      channels <= 2 &&
      sampleRate >= 8000 &&
      sampleRate <= 48000 &&
      blockAlign == channels * 2 &&
      byteRate == sampleRate * channels * 2;
  return ok ? (sampleRate: sampleRate, channels: channels) : null;
}
