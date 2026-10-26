import 'package:flutter/material.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';

const _emptyKey = ValueKey<String>('pane-empty');

// 대화 창. 자체 Navigator라 대화 화면의 뒤로·종료(pop)가 이 창 안에서만 돎
// 대화 쪽 스낵바도 이 창 안에만 뜨게 ScaffoldMessenger를 따로 둠
class ChatPane extends StatefulWidget {
  const ChatPane({
    required this.conversationId,
    required this.wide,
    required this.onClosed,
    required this.onSettled,
    super.key,
  });

  final String? conversationId;

  // 2단이면 목록에서 고른 대화로 바로 바꾸고, 좁은 창이면 플랫폼 전환(iOS 스와이프 뒤로·Android 예측형 뒤로)으로 띄움
  final bool wide;

  // 대화 화면이 스스로 닫혔을 때(뒤로·Esc·대화 종료)
  final VoidCallback onClosed;

  // 대화 화면이 다 들어와 멈췄는지(전환·뒤로 제스처 중이 아님). 좁은 창은 그동안만 밑의 목록을 안 그림
  final ValueChanged<bool> onSettled;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    closePaneChat = _close;
  }

  @override
  void dispose() {
    if (closePaneChat == _close) closePaneChat = null;
    super.dispose();
  }

  // 뒤로와 같은 길이라 대화 안 검색 중이면 검색만 닫힘 (PopScope)
  Future<bool> _close() async =>
      await _navigator.currentState?.maybePop() ?? false;

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId;
    // 앱 루트에 대화상자·화면이 떠 있으면 대화를 뒤로로 닫지 않음: 이 창 Navigator는 맨 위를 따로 세서
    // 예측형 뒤로·스와이프가 위의 대화상자 대신 밑의 대화를 닫았음
    final front = ModalRoute.isCurrentOf(context) ?? true;
    // Android 뒤로가 앱을 닫기 전에 이 창의 대화부터 닫게 함
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigator.currentState?.maybePop(),
      child: ScaffoldMessenger(
        child: Navigator(
          key: _navigator,
          transitionDelegate: widget.wide
              ? const _InstantTransitions()
              : const DefaultTransitionDelegate<void>(),
          pages: [
            // 좁은 창에선 비어 있어서 대화가 들고 날 때 밑의 목록이 보임
            MaterialPage<void>(
              key: _emptyKey,
              child: widget.wide
                  ? const _NoChatOpen()
                  : const SizedBox.shrink(),
            ),
            if (id != null)
              MaterialPage<void>(
                key: ValueKey<String>(id),
                child: PopScope<void>(
                  canPop: front,
                  child: _SettleWatch(
                    onSettled: widget.onSettled,
                    child: ChatRoomScreen(conversationId: id),
                  ),
                ),
              ),
          ],
          onDidRemovePage: (page) {
            // 다른 대화로 바뀌며 빠진 페이지는 무시 (지금 띄운 대화가 닫힐 때만)
            if (id != null && page.key == ValueKey<String>(id)) {
              widget.onClosed();
            }
          },
        ),
      ),
    );
  }
}

// 대화 경로의 전환이 끝났고 뒤로 제스처(iOS 스와이프·Android 예측형 뒤로)도 없는지 알림.
// 빌드 중엔 위 위젯 상태를 못 바꿔서 처음 값은 다음 프레임에 알림
class _SettleWatch extends StatefulWidget {
  const _SettleWatch({required this.onSettled, required this.child});

  final ValueChanged<bool> onSettled;
  final Widget child;

  @override
  State<_SettleWatch> createState() => _SettleWatchState();
}

class _SettleWatchState extends State<_SettleWatch> {
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _unlisten();
    _route = route
      ?..animation?.addStatusListener(_onStatus)
      ..navigator?.userGestureInProgressNotifier.addListener(_report);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
  }

  void _onStatus(AnimationStatus _) => _report();

  void _report() {
    final route = _route;
    widget.onSettled(
      route != null &&
          route.animation?.status == AnimationStatus.completed &&
          !(route.navigator?.userGestureInProgress ?? false),
    );
  }

  void _unlisten() {
    _route?.animation?.removeStatusListener(_onStatus);
    _route?.navigator?.userGestureInProgressNotifier.removeListener(_report);
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// 2단에서 목록으로 대화를 바꾸거나 지울 때는 밀려 들어오는 전환 없이 바로 바꿈 (뒤로·Esc로 닫는 건 평소 전환)
class _InstantTransitions extends TransitionDelegate<void> {
  const _InstantTransitions();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
    pageRouteToPagelessRoutes,
  }) {
    final results = <RouteTransitionRecord>[];
    void exit(RouteTransitionRecord? location) {
      final route = locationToExitingPageRoute[location];
      if (route == null) return;
      if (route.isWaitingForExitingDecision) {
        for (final record in [route, ...?pageRouteToPagelessRoutes[route]]) {
          if (record.isWaitingForExitingDecision) {
            record.markForComplete(record.route.currentResult);
          }
        }
      }
      results.add(route);
      exit(route);
    }

    exit(null);
    for (final page in newPageRouteHistory) {
      if (page.isWaitingForEnteringDecision) page.markForAdd();
      results.add(page);
      exit(page);
    }
    return results;
  }
}

class _NoChatOpen extends StatelessWidget {
  const _NoChatOpen();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: EmptyState(
        art: EmptyStateArt.bubbles,
        title: s.t('home.noChatOpenTitle'),
        body: s.t('home.noChatOpenBody'),
      ),
    );
  }
}
