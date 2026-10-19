import 'package:flutter/material.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';

// 이 폭부터 목록 옆에 대화를 띄움 (Material 확장 창 기준, iPad 가로·데스크톱 창)
const kTwoPaneMinWidth = 840.0;
const kListPaneWidth = 360.0;

const _emptyKey = ValueKey<String>('pane-empty');

// 목록 옆 대화 창. 자체 Navigator라 대화 화면의 뒤로·종료(pop)가 이 창 안에서만 돎
// 대화 쪽 스낵바도 이 창 안에만 뜨게 ScaffoldMessenger를 따로 둠
class ChatPane extends StatefulWidget {
  const ChatPane({
    required this.conversationId,
    required this.onClosed,
    super.key,
  });

  final String? conversationId;

  // 대화 화면이 스스로 닫혔을 때(뒤로·Esc·대화 종료)
  final VoidCallback onClosed;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId;
    // Android 뒤로가 앱을 닫기 전에 이 창의 대화부터 닫게 함
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigator.currentState?.maybePop(),
      child: ScaffoldMessenger(
        child: Navigator(
          key: _navigator,
          pages: [
            const _PanePage(key: _emptyKey, child: _NoChatOpen()),
            if (id != null)
              _PanePage(
                key: ValueKey<String>(id),
                child: ChatRoomScreen(conversationId: id),
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

// 대화를 바꿀 때 창 안에서 밀려 들어오는 전환 없이 바로 바꿈
class _PanePage extends Page<void> {
  const _PanePage({required super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => PageRouteBuilder<void>(
    settings: this,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => child,
  );
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

// 이 창 크기를 MediaQuery로 내려 줌: 말풍선 최대 폭·좁은 폭 판단이 창 전체가 아니라 이 창을 봄
// 안쪽 가장자리의 안전 영역 여백은 뺌
class PaneMedia extends StatelessWidget {
  const PaneMedia({
    required this.child,
    this.removeLeft = false,
    this.removeRight = false,
    super.key,
  });

  final Widget child;
  final bool removeLeft;
  final bool removeRight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MediaQuery(
      data: MediaQuery.of(context)
          .removePadding(removeLeft: removeLeft, removeRight: removeRight)
          .copyWith(size: constraints.biggest),
      child: child,
    ),
  );
}
