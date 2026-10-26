import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/tokens.dart';

// 자동 새로고침 카운트다운도 여기서 돎: 언제 다시 훑을지는 화면을 보는 사람 쪽 관심사라 UI에 둠 (DiscoveryController는 mDNS 상태만 듦)
class DiscoveryRefreshRow extends ConsumerStatefulWidget {
  const DiscoveryRefreshRow({super.key});

  @override
  ConsumerState<DiscoveryRefreshRow> createState() =>
      _DiscoveryRefreshRowState();
}

class _DiscoveryRefreshRowState extends ConsumerState<DiscoveryRefreshRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: kDiscoveryRefresh,
            animationBehavior: AnimationBehavior.preserve,
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _refresh();
          })
          ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.read(discoveryControllerProvider.notifier).refresh();
    _controller.forward(from: 0);
  }

  // 손으로 누르면 mDNS 재스캔에 더해 bind 주소가 바뀌었는지도 봄 (자동 주기의 주소 확인은 ServerController 타이머 몫)
  void _manualRefresh() {
    unawaited(ref.read(serverControllerProvider.notifier).refreshNetwork());
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final remaining =
                ((1 - _controller.value) * kDiscoveryRefresh.inSeconds)
                    .ceil()
                    .clamp(0, kDiscoveryRefresh.inSeconds);
            return Text(
              s.t('home.refreshingIn', {'seconds': '$remaining'}),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.refresh, size: 18, color: color),
          tooltip: s.t('home.refreshDevices'),
          onPressed: _manualRefresh,
        ),
      ],
    );
  }
}
