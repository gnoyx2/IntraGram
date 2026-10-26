part of '../voice_recorder.dart';

// 진짜 파형 대신 녹음 스트림의 dB 레벨로 그린 근사치. 지터를 자체 ticker로 돌려서 부모의 1초 갱신과 상관없이 부드럽게 흐름
class _WaveformBars extends StatefulWidget {
  const _WaveformBars({
    required this.level,
    required this.elapsed,
    required this.color,
  });

  final double level;
  final Duration elapsed;
  final Color color;

  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _weights = [0.4, 0.7, 1.0, 0.7, 0.4, 0.8, 0.5];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reduce-motion이면 무한 반복 지터를 아예 안 돌림 (음량/시간 표시는 부모가 계속 다시 그림)
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _jitter(double t, int i) => (math.sin(t + i) + 1) / 2;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _weights.length; i++)
              Flexible(
                child: _Bar(
                  height:
                      (4 +
                              (widget.level * _weights[i] * 0.7 +
                                      (reduceMotion
                                          ? 0
                                          : _jitter(t, i) * 0.3)) *
                                  16)
                          .clamp(4.0, 20.0)
                          .toDouble(),
                  color: widget.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: motionDuration(context, const Duration(milliseconds: 100)),
    width: 3,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
  );
}

String _format(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
