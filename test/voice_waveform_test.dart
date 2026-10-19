import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/transfer_tile.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

Uint8List _pcm(Iterable<int> samples) {
  final list = samples.toList();
  final data = ByteData(list.length * 2);
  for (var i = 0; i < list.length; i++) {
    data.setInt16(i * 2, list[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('a recorder WAV gives 28 bars that follow the real loudness', () {
    // 앞 절반은 무음, 뒤 절반은 큰 소리
    const perBar = 400;
    final wav = encodePcm16WavForTesting(
      _pcm([
        for (var i = 0; i < 28 * perBar; i++)
          i < 14 * perBar ? 0 : (i.isEven ? 20000 : -20000),
      ]),
    );

    final bars = voiceWaveformForTesting(wav);

    expect(bars, hasLength(28));
    expect(bars.take(14), everyElement(closeTo(0.18, 1e-9)));
    expect(bars.skip(14), everyElement(closeTo(1, 1e-9)));
  });

  test('the length comes from the header byte rate before playback', () {
    final wav = encodePcm16WavForTesting(
      _pcm(List<int>.filled(16000, 0)),
      sampleRate: 16000,
    );
    expect(voiceDurationForTesting(wav), const Duration(seconds: 1));
  });

  test('foreign or broken bytes from a peer never throw', () {
    final noFormat = Uint8List.fromList([
      ...'RIFF'.codeUnits,
      0,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...'data'.codeUnits,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
    ]);
    final hugeChunk = Uint8List.fromList([
      ...'RIFF'.codeUnits,
      0,
      0,
      0,
      0,
      ...'WAVEJUNK'.codeUnits,
      0xFF,
      0xFF,
      0xFF,
      0x7F,
    ]);
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(List<int>.filled(64, 1)),
      noFormat,
      hugeChunk,
    ]) {
      expect(voiceWaveformForTesting(bytes), hasLength(28));
      expect(voiceDurationForTesting(bytes), Duration.zero);
    }
  });
}
