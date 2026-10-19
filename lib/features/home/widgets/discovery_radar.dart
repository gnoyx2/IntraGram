import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state_art.dart';

// "이 네트워크에서" 섹션이 빈 이유. 이유마다 문구/아이콘/보조 액션이 다름
enum DiscoveryEmptyReason { searching, noDevices, noWifi, notPrivate, error }

// 레이더 스위프·펄스는 실제로 찾는 중일 때만 돎 (스캔은 DiscoveryEngine이 하고 이 위젯은 상태 표시만)
// 한 바퀴 3.2초, 펄스는 바퀴당 두 번
class DiscoveryRadar extends StatefulWidget {
  const DiscoveryRadar({
    required this.reason,
    this.onRefresh,
    this.onManualConnect,
    super.key,
  });

  final DiscoveryEmptyReason reason;

  // error일 때만 보임 (죽은 스캐너를 다시 돌림)
  final VoidCallback? onRefresh;

  // noDevices일 때만 보임 (mDNS 대신 IP로 직접 연결)
  final VoidCallback? onManualConnect;

  @override
  State<DiscoveryRadar> createState() => _DiscoveryRadarState();
}

class _DiscoveryRadarState extends State<DiscoveryRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant DiscoveryRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reason != widget.reason) _syncTicker();
  }

  // reduce-motion이거나 찾는 중이 아니면 무한 반복 애니메이션을 안 돌림 (배터리 + 전정 감각 민감 사용자 배려)
  void _syncTicker() {
    final shouldAnimate =
        widget.reason == DiscoveryEmptyReason.searching &&
        !MediaQuery.of(context).disableAnimations;
    if (!shouldAnimate) {
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    // iOS·macOS는 첫 탐색 때 '로컬 네트워크' 허용 창이 뜸: 왜 묻는지 그 순간 화면에 같이 보이게 함
    // (첫 실행 화면을 따로 두면 그걸 봤다는 표시를 디스크에 남겨야 해서 RAM 전용 약속과 어긋남)
    final apple = const {
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    final (icon, color, text) = switch (widget.reason) {
      DiscoveryEmptyReason.searching => (
        Icons.wifi_tethering,
        scheme.primary,
        apple
            ? '${s.t('home.lookingForDevices')}\n'
                  '${s.t('home.localNetworkWhy')}'
            : s.t('home.lookingForDevices'),
      ),
      DiscoveryEmptyReason.noDevices => (
        Icons.wifi_tethering_off,
        scheme.onSurfaceVariant,
        s.t('home.noDevicesFound'),
      ),
      DiscoveryEmptyReason.noWifi => (
        Icons.wifi_off,
        scheme.onSurfaceVariant,
        s.t('home.noWifi'),
      ),
      DiscoveryEmptyReason.notPrivate => (
        Icons.public,
        scheme.onSurfaceVariant,
        s.t('home.notPrivate'),
      ),
      DiscoveryEmptyReason.error => (
        Icons.error_outline,
        scheme.error,
        // Linux 탐색은 avahi-daemon(D-Bus)에 기대서, 멈췄다면 대개 데몬이 없음
        s.t(
          defaultTargetPlatform == TargetPlatform.linux
              ? 'home.discoveryErrorLinux'
              : 'home.discoveryError',
        ),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 120,
            child: ExcludeSemantics(
              child: widget.reason == DiscoveryEmptyReason.searching
                  ? RepaintBoundary(
                      child: CustomPaint(
                        painter: EmptyStateArtPainter(
                          art: EmptyStateArt.radar,
                          colorScheme: scheme,
                          chat: context.chat,
                          motion: _controller,
                        ),
                      ),
                    )
                  : Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.10),
                          border: Border.all(
                            color: color.withValues(alpha: 0.28),
                            width: AppBorder.hairline,
                          ),
                        ),
                        child: Icon(icon, size: 28, color: color),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (widget.reason == DiscoveryEmptyReason.error &&
              widget.onRefresh != null)
            TextButton(
              onPressed: widget.onRefresh,
              child: Text(s.t('common.retry')),
            )
          else if (widget.reason == DiscoveryEmptyReason.noDevices &&
              widget.onManualConnect != null)
            TextButton(
              onPressed: widget.onManualConnect,
              child: Text(s.t('home.connectByIp')),
            ),
        ],
      ),
    );
  }
}
