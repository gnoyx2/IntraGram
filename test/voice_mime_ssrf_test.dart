import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/core/voice/voice_wav.dart';
import 'package:intragram/network/protocol.dart';

// 상대가 보낸 음성 바이트는 16비트 PCM WAV로 검사를 통과해야만 재생기에 닿음
// (재생목록·다른 컨테이너로 해석돼 외부 주소를 가져오는 경로를 막음)
void main() {
  Uint8List wav({
    int format = 1,
    int channels = 1,
    int rate = 16000,
    int bits = 16,
    int byteRate = 32000,
    int blockAlign = 2,
    List<int> pcm = const [1, 0, 2, 0],
  }) {
    final out = ByteData(44 + pcm.length)
      ..setUint32(4, 36 + pcm.length, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, format, Endian.little)
      ..setUint16(22, channels, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, blockAlign, Endian.little)
      ..setUint16(34, bits, Endian.little)
      ..setUint32(40, pcm.length, Endian.little);
    const tags = {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'};
    tags.forEach((at, tag) {
      for (var i = 0; i < 4; i++) {
        out.setUint8(at + i, tag.codeUnitAt(i));
      }
    });
    final bytes = out.buffer.asUint8List()..setAll(44, pcm);
    return bytes;
  }

  test('voice offer MIME is fixed at the wire boundary', () {
    final bytes = wav();
    final offer = InnerFrame.fileOffer(
      id: 'voice',
      attempt: 'attempt',
      mode: 'push',
      name: 'voice.wav',
      size: bytes.length,
      mime: 'audio/mpegurl',
      voice: true,
    );
    expect((InboundInner.fromJson(offer) as FileOfferInner).mime, 'audio/wav');
  });

  test('a recorder-shaped WAV passes', () {
    final parsed = parsePcm16Wav(wav())!;
    expect((parsed.sampleRate, parsed.channels), (16000, 1));
    expect(parsed.pcm, [1, 0, 2, 0]);
  });

  test('playlists and forged or unusual WAV headers never reach a player', () {
    for (final bytes in [
      Uint8List.fromList('#EXTM3U\nhttps://example.com/secret'.codeUnits),
      Uint8List.fromList('RIFF'.codeUnits),
      Uint8List.fromList('RIFF0000M3U8'.codeUnits),
      wav(format: 3), // float
      wav(bits: 8, byteRate: 16000, blockAlign: 1),
      wav(rate: 96000, byteRate: 192000),
      wav(channels: 6, byteRate: 192000, blockAlign: 12),
      wav(byteRate: 1234), // 머리 값이 서로 안 맞음
    ]) {
      expect(parsePcm16Wav(bytes), isNull);
      expect(loadVoiceClip(bytes), throwsFormatException);
    }
  });
}
