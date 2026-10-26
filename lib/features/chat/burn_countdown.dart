import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 1초마다 갱신되며 0에서 멈춤. 실제 소각은 store 타이머가 기준이므로
// 이 위젯은 그 시점을 앞당기거나 늦추지 않음
class BurnCountdown extends StatefulWidget {
  const BurnCountdown({required this.burnAt, required this.color, super.key});

  final DateTime burnAt;
  final Color color;

  @override
  State<BurnCountdown> createState() => _BurnCountdownState();
}

class _BurnCountdownState extends State<BurnCountdown> {
  Timer? _ticker;
  int _seconds = 0;

  // 올림 계산으로 남은 초를 다시 잡고, 0에 막 닿을 때만 햅틱을 울리고 티커를 멈춤.
  // setState는 호출부가 감쌈
  void _recompute() {
    final remainingMs = widget.burnAt.difference(DateTime.now()).inMilliseconds;
    final next = remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
    final crossedToZero = next == 0 && _seconds != 0;
    _seconds = next;
    if (next == 0) {
      _ticker?.cancel();
      _ticker = null;
      if (crossedToZero) AppHaptics.lightImpact();
    }
  }

  void _restartTicker() {
    _ticker?.cancel();
    _recompute();
    if (_seconds > 0) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_recompute);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _restartTicker();
  }

  @override
  void didUpdateWidget(BurnCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.burnAt != widget.burnAt) setState(_restartTicker);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 낭독은 큰 단위로 (1시간을 '3600초'로 읽지 않음). 화면의 숫자는 따로 안 읽혀 두 번 안 들림
    final (n, one, other) = _seconds >= 3600
        ? (_seconds ~/ 3600, 'a11y.burnHour', 'a11y.burnHours')
        : _seconds >= 60
        ? (_seconds ~/ 60, 'a11y.burnMinute', 'a11y.burnMinutes')
        : (_seconds, 'a11y.burnSecond', 'a11y.burnSeconds');
    return Semantics(
      label: s.plural(n, one: s.t(one), other: s.t(other)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_bottom_rounded,
            // 아이콘은 텍스트 스케일을 자동으로 안 따라가서 직접 키움
            size: MediaQuery.textScalerOf(context).scale(12),
            color: widget.color,
          ),
          const SizedBox(width: AppSpacing.xxs),
          // 말풍선 메타 행의 시각과 같은 글자 상자라 모래시계·숫자·시각 중심이 한 줄에 맞음
          ExcludeSemantics(
            child: Text(
              '$_seconds',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.color,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
