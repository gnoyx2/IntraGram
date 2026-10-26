part of '../chat_app_bar.dart';

// 재연결이 끝날 때까지 버튼을 잠금. 실패해도(마지막 주소가 죽음) 배너가 남아서 다시 누를 수 있고
// 막힌 이유는 홈 연결과 같은 스낵바로 알림
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    this.onReconnect,
    this.blocked = false,
    this.onUnblock,
    super.key,
  });

  // 없으면 내가 연 방: 다시 걸 상대가 하나가 아니라서 버튼 대신 멤버가 각자 다시 들어온다고 알림
  final Future<void> Function()? onReconnect;

  // 내가 차단한 상대: 재연결 대신 차단 해제를 보임 (차단 중엔 다이얼해도 거절됨)
  final bool blocked;
  final VoidCallback? onUnblock;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _reconnecting = false;

  Future<void> _tap() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    setState(() => _reconnecting = true);
    try {
      await widget.onReconnect!();
    } on PeerUnreachableException catch (e) {
      messenger.showSnackBar(connectFailureSnackBar(s, e.reason));
    } on SecurityException {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('connect.notPrivate'))),
      );
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              widget.blocked ? Icons.block : Icons.wifi_off,
              size: MediaQuery.textScalerOf(context).scale(18),
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.blocked
                      ? s.t('chat.blockedBanner')
                      : widget.onReconnect == null
                      ? s.t('chat.roomEmptyBanner')
                      : _reconnecting
                      ? s.t('sys.reconnecting')
                      : s.t('sys.disconnected'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            // 아주 큰 글씨에선 버튼 글자도 줄바꿈되게 남은 폭을 글과 나눠 가짐 (안 그러면 가로로 넘침)
            if (widget.blocked || widget.onReconnect != null)
              Flexible(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: widget.blocked
                      ? widget.onUnblock
                      : (_reconnecting ? null : _tap),
                  child: Text(
                    s.t(widget.blocked ? 'chat.unblock' : 'sys.reconnect'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
