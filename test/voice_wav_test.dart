import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

void main() {
  group('encodePcm16WavForTesting', () {
    test('writes the standard 44-byte RIFF/WAVE/fmt/data header', () {
      final pcm = Uint8List.fromList([1, 2, 3, 4]); // 2개 샘플, 16-bit
      final wav = encodePcm16WavForTesting(pcm, sampleRate: 16000);
      final view = ByteData.sublistView(wav);

      expect(wav.length, 44 + 4);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

      expect(view.getUint32(4, Endian.little), 36 + 4); // RIFF 청크 크기
      expect(view.getUint32(16, Endian.little), 16); // fmt 청크 크기
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // 모노
      expect(view.getUint32(24, Endian.little), 16000); // 샘플레이트
      expect(view.getUint32(28, Endian.little), 16000 * 2); // 바이트레이트
      expect(view.getUint16(32, Endian.little), 2); // block align
      expect(view.getUint16(34, Endian.little), 16); // 샘플당 비트 수
      expect(view.getUint32(40, Endian.little), 4); // data 청크 크기

      expect(wav.sublist(44), [1, 2, 3, 4]);
    });

    test('drops a trailing unpaired byte instead of corrupting the header', () {
      final pcm = Uint8List.fromList([1, 2, 3]); // 1.5 샘플: 홀수 길이
      final wav = encodePcm16WavForTesting(pcm, sampleRate: 16000);
      final view = ByteData.sublistView(wav);

      expect(wav.length, 44 + 2);
      expect(view.getUint32(40, Endian.little), 2);
      expect(wav.sublist(44), [1, 2]);
    });

    test('an empty PCM buffer still produces a valid, playable header', () {
      final wav = encodePcm16WavForTesting(Uint8List(0));
      expect(wav.length, 44);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(40, Endian.little), 0);
    });
  });
}
