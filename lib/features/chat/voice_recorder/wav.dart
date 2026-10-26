part of '../voice_recorder.dart';

// 테스트엔 record 플랫폼 채널이 없어서 헤더 합성(순수 함수)만 따로 떼어 검증함
@visibleForTesting
Uint8List encodePcm16WavForTesting(
  Uint8List pcm, {
  int sampleRate = kVoiceSampleRate,
}) => _encodePcm16Wav(pcm, sampleRate: sampleRate);

// 인코딩 없이 44바이트 표준 WAV 헤더만 붙임. pcm 길이가 홀수면(2바이트 샘플이 덜 찬 경우) 마지막 바이트를 버림
Uint8List _encodePcm16Wav(Uint8List pcm, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  final dataLength = pcm.length - (pcm.length.isOdd ? 1 : 0);
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;

  final header = ByteData(44)
    ..setUint32(4, 36 + dataLength, Endian.little)
    ..setUint32(16, 16, Endian.little) // fmt 청크 크기
    ..setUint16(20, 1, Endian.little) // 오디오 포맷 1 = PCM
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, bitsPerSample, Endian.little)
    ..setUint32(40, dataLength, Endian.little);
  _writeAscii(header, 0, 'RIFF');
  _writeAscii(header, 8, 'WAVE');
  _writeAscii(header, 12, 'fmt ');
  _writeAscii(header, 36, 'data');

  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(Uint8List.sublistView(pcm, 0, dataLength)))
      .takeBytes();
}

void _writeAscii(ByteData buffer, int offset, String ascii) {
  for (var i = 0; i < ascii.length; i++) {
    buffer.setUint8(offset + i, ascii.codeUnitAt(i));
  }
}
