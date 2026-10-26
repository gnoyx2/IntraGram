part of '../transfer_tile.dart';

const int _kWaveBars = 28;

String _formatClock(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// 16비트 PCM WAV(녹음기가 만드는 유일한 형식)면 구간별 평균 진폭으로 실제 파형을 만듦
// 다른 바이트면 등간격 바이트 표본으로 대신함. 같은 파일은 항상 같은 모양
// 긴 녹음도 막대당 표본을 512개 안팎만 읽어서 첫 그리기가 멈추지 않음
List<double> _waveformFor(Uint8List bytes) {
  const floor = 0.18;
  final pcm = parsePcm16Wav(bytes)?.samples;
  final count = pcm == null ? 0 : pcm.lengthInBytes ~/ 2;
  if (pcm == null || count < _kWaveBars) return _byteWaveform(bytes);
  final per = count ~/ _kWaveBars;
  final stride = math.max(1, per ~/ 512);
  final levels = List<double>.generate(_kWaveBars, (bar) {
    var sum = 0;
    var taken = 0;
    for (var i = bar * per; i < (bar + 1) * per; i += stride) {
      sum += pcm.getInt16(i * 2, Endian.little).abs();
      taken++;
    }
    return sum / taken;
  });
  final loudest = levels.reduce(math.max);
  if (loudest == 0) return List<double>.filled(_kWaveBars, floor);
  // 제곱근으로 작은 소리도 눈에 띄게 끌어올림
  return [
    for (final level in levels)
      floor + (1 - floor) * math.sqrt(level / loudest),
  ];
}

// 재생 전에도 길이를 보이도록 머리에서 계산함. 형식을 모르면 0
Duration _wavDuration(Uint8List bytes) =>
    parsePcm16Wav(bytes)?.duration ?? Duration.zero;

// 상대가 보낸 바이트를 파싱하므로 형식 깨짐·잘린 머리에도 안 죽는지 테스트가 이 창으로 확인함
@visibleForTesting
List<double> voiceWaveformForTesting(Uint8List bytes) => _waveformFor(bytes);

@visibleForTesting
Duration voiceDurationForTesting(Uint8List bytes) => _wavDuration(bytes);

// 형식을 모르는 바이트는 등간격 바이트 값을 진폭처럼 씀 (장식용 근사치)
List<double> _byteWaveform(Uint8List bytes) {
  if (bytes.isEmpty) return List<double>.filled(_kWaveBars, 0.25);
  final step = (bytes.length / _kWaveBars).floor().clamp(1, bytes.length);
  return [
    for (var i = 0; i < _kWaveBars; i++)
      0.25 + (bytes[(i * step) % bytes.length] / 255) * 0.75,
  ];
}

// 재생 위치 이벤트는 띄엄띄엄 와서 사이를 선형으로 이어 채움이 끊기지 않게 함
class _WaveformBars extends StatelessWidget {
  const _WaveformBars({
    required this.bars,
    required this.progress,
    required this.played,
    required this.idle,
  });

  final List<double> bars;
  final double progress;
  final Color played;
  final Color idle;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: progress),
    duration: motionDuration(context, const Duration(milliseconds: 220)),
    builder: (context, value, _) => CustomPaint(
      painter: _WaveformPainter(
        bars: bars,
        progress: value,
        played: played,
        idle: idle,
      ),
    ),
  );
}

// 둥근 막대를 한 경로로 모아 두 번만 그림. 재생된 구간은 진행 위치에서 픽셀 단위로 잘라 액센트로 덮음
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.idle,
  });

  final List<double> bars;
  final double progress;
  final Color played;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / bars.length;
    final barWidth = math.min(3.0, slot * 0.6);
    final radius = Radius.circular(barWidth / 2);
    final path = Path();
    for (var i = 0; i < bars.length; i++) {
      final height = math.max(barWidth, size.height * bars[i]);
      final left = i * slot + (slot - barWidth) / 2;
      final top = (size.height - height) / 2;
      path.addRRect(
        RRect.fromLTRBR(left, top, left + barWidth, top + height, radius),
      );
    }
    canvas.drawPath(path, Paint()..color = idle);
    if (progress <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    canvas.drawPath(path, Paint()..color = played);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.played != played ||
      oldDelegate.idle != idle ||
      !identical(oldDelegate.bars, bars);
}
