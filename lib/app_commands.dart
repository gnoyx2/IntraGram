import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intragram/widgets/keyboard_access.dart';
import 'package:flutter/services.dart';

import 'features/chat/open_chat.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';

// 어느 화면에서든 같은 키: ⌘/Ctrl+, 설정 · ⌘/Ctrl+F 검색 · ⌘/Ctrl+N 새 연결 ·
// ⌘/Ctrl+W·Esc 지금 화면(대화상자·메뉴 포함) 닫기 · ⌘/Ctrl +·−·0 글자 크기
// macOS 메뉴 막대도 같은 명령을 부름
// 대화 화면의 ⌘F(대화 안 검색)처럼 안쪽에서 먼저 잡은 키는 여기까지 안 옴
class AppCommands extends StatefulWidget {
  const AppCommands({
    required this.navigatorKey,
    required this.unlocked,
    required this.onNewConnection,
    required this.child,
    this.onTextSize,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  // 잠금 화면에선 설정·검색·새 연결을 안 띄움 (닫기는 대화상자에도 필요해서 늘 동작)
  final bool unlocked;

  final void Function(BuildContext navigatorContext) onNewConnection;
  final Widget child;

  // +1 크게, -1 작게, 0 100%로
  final void Function(int step)? onTextSize;

  @override
  State<AppCommands> createState() => _AppCommandsState();
}

class _AppCommandsState extends State<AppCommands> {
  static const _menu = MethodChannel('intragram/menu');

  @override
  void initState() {
    super.initState();
    _menu.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'settings':
          _open(SettingsScreen.route);
        case 'search':
          _search();
        case 'textSize' when call.arguments is int:
          final step = call.arguments as int;
          if (step >= -1 && step <= 1) widget.onTextSize?.call(step);
        case 'newConnection':
          _newConnection();
        case 'close':
          _close();
      }
    });
  }

  @override
  void dispose() {
    _menu.setMethodCallHandler(null);
    super.dispose();
  }

  // 키보드 초점이 있는 경로 = 맨 위 화면이나 떠 있는 대화상자·메뉴
  Route<Object?>? get _focusedRoute {
    final context = primaryFocus?.context;
    return context == null ? null : ModalRoute.of(context);
  }

  // 대화상자·메뉴 위로는 새 화면을 안 띄움
  bool get _canOpen => widget.unlocked && _focusedRoute is! PopupRoute;

  // 이미 그 화면에 있으면 또 쌓지 않음
  void _open(Route<void> Function() build) {
    final navigator = widget.navigatorKey.currentState;
    final route = build();
    if (!_canOpen ||
        navigator == null ||
        _focusedRoute?.settings.name == route.settings.name) {
      return;
    }
    unawaited(navigator.push(route));
  }

  void _search() {
    if (!_canOpen) return;
    final context = primaryFocus?.context;
    if (context != null &&
        Actions.maybeFind<SearchMessagesIntent>(context) != null) {
      Actions.invoke(context, const SearchMessagesIntent());
    } else {
      _open(SearchScreen.route);
    }
  }

  void _newConnection() {
    final context = widget.navigatorKey.currentContext;
    if (_canOpen && context != null) widget.onNewConnection(context);
  }

  // 초점이 있는 쪽 Navigator(2단의 대화 창 포함)에서 닫음. 거기 닫을 게 없으면(2단 목록에 초점 등) 열린 대화를 닫음
  void _close() {
    final context = primaryFocus?.context ?? widget.navigatorKey.currentContext;
    if (context == null) return;
    unawaited(
      Navigator.maybePop(context).then((popped) async {
        if (!popped) await closePaneChat?.call();
      }),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      // Cmd/Ctrl 둘 다 등록해서 플랫폼 분기를 없앰
      for (final meta in const [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.comma,
          meta: meta,
          control: !meta,
        ): () =>
            _open(SettingsScreen.route),
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: meta,
          control: !meta,
        ): () =>
            _open(SearchScreen.route),
        SingleActivator(LogicalKeyboardKey.keyN, meta: meta, control: !meta):
            _newConnection,
        SingleActivator(LogicalKeyboardKey.keyW, meta: meta, control: !meta):
            _close,
        // ⌘+는 자판에 따라 Shift+= 라서 둘 다
        for (final shift in const [false, true])
          SingleActivator(
            LogicalKeyboardKey.equal,
            meta: meta,
            control: !meta,
            shift: shift,
          ): () =>
              widget.onTextSize?.call(1),
        SingleActivator(
          LogicalKeyboardKey.numpadAdd,
          meta: meta,
          control: !meta,
        ): () =>
            widget.onTextSize?.call(1),
        SingleActivator(
          LogicalKeyboardKey.minus,
          meta: meta,
          control: !meta,
        ): () =>
            widget.onTextSize?.call(-1),
        SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          meta: meta,
          control: !meta,
        ): () =>
            widget.onTextSize?.call(-1),
        SingleActivator(
          LogicalKeyboardKey.digit0,
          meta: meta,
          control: !meta,
        ): () =>
            widget.onTextSize?.call(0),
      },
      const SingleActivator(LogicalKeyboardKey.escape): _close,
    },
    child: Actions(
      actions: {
        SearchMessagesIntent: CallbackAction<SearchMessagesIntent>(
          onInvoke: (_) => _open(SearchScreen.route),
        ),
      },
      child: widget.child,
    ),
  );
}
