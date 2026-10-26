import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/chat/widgets/typing_dots.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/press_scale.dart';
import 'package:intragram/widgets/readable_list.dart';

part 'message_list/entries.dart';
part 'message_list/entry_builder.dart';
part 'message_list/view.dart';
part 'message_list/burn_ghost.dart';

// reverse 목록이라 새 메시지가 스크롤 점프 없이 바닥에 붙음
class MessageList extends StatefulWidget {
  const MessageList({
    required this.messages,
    this.unreadOnOpen = 0,
    this.onReply,
    this.highlightMessageId,
    this.focusMessageId,
    this.peerTyping = false,
    super.key,
  });

  final List<EphemeralMessage> messages;

  final int unreadOnOpen;

  final bool peerTyping;

  final void Function(String messageId)? onReply;

  final String? highlightMessageId;

  final String? focusMessageId;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scroll = ScrollController();
  // 목록 자체의 Tab 칸. 키보드로 스크롤하다 포커스한 말풍선이 화면 밖으로 사라지면 여기로 포커스를 옮겨 다음 키가 이어짐
  final FocusNode _listFocus = FocusNode(debugLabel: 'messages');
  bool _showJump = false;

  // 점프와 소각 크기 재기에 쓰는 행 키 (build마다 살아 있는 id로 가지치기)
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};

  // 처음 열 때 있던 메시지와 한 번이라도 빌드된 메시지의 id. 도착 애니메이션은 처음 빌드될 때 한 번만 돌아서
  // 스크롤로 행이 다시 만들어져도 또 안 튐
  late final Set<String> _seen;

  // 소각 타이머로 막 지워진 메시지의 고스트. 사라지는 애니메이션이 끝날 때까지 더 그림
  final Map<String, _BurnGhostSpec> _burning = <String, _BurnGhostSpec>{};

  // 답장 인용을 눌러 온 메시지의 일회성 깜빡임 (검색 점프 강조와 별개)
  String? _flashId;

  void _jumpToMessage(String id) {
    _focus(id);
    setState(() => _flashId = id);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _flashId == id) setState(() => _flashId = null);
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _seen = widget.messages.map((m) => m.id).toSet();
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focus = widget.focusMessageId;
    if (focus != null && focus != oldWidget.focusMessageId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(focus));
    }
    _detectBurns(oldWidget.messages);
  }

  // 있다가 사라진 메시지 중 타이머가 걸려 있던 것만 소각 애니메이션을 그림 (대화 삭제 등은 그냥 사라짐)
  void _detectBurns(List<EphemeralMessage> previous) {
    final liveIds = widget.messages.map((m) => m.id).toSet();
    for (final m in previous) {
      if (liveIds.contains(m.id) || m.ttlSeconds <= 0) continue;
      if (_burning.containsKey(m.id)) continue;
      final box =
          _rowKeys[m.id]?.currentContext?.findRenderObject() as RenderBox?;
      _burning[m.id] = _BurnGhostSpec(
        id: m.id,
        createdAt: m.createdAt,
        mine: m.isMine,
        // 화면 밖이라 못 재면 평범한 말풍선 크기로 대신함
        size: box?.size ?? const Size(160, 44),
      );
      final id = m.id;
      Future.delayed(
        motionDuration(context, const Duration(milliseconds: 320)),
        () {
          if (mounted) setState(() => _burning.remove(id));
        },
      );
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  // 빌드돼 있으면 바로 맞추고, 화면 밖이면 평균 행 높이(76px)로 대충 뛴 뒤 빌드되면 맞춤.
  // 말풍선 크기 편차가 크면 한 번에 안 맞지만 post-frame 재시도로 보정됨 (수백 개까진 충분)
  void _focus(String id) {
    if (!mounted) return;
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx != null) {
      // ensureVisible 애니메이션 도중엔 스크롤 리스너가 중간 offset을 봐서 맨 아래로 버튼이 깜빡임.
      // 멈춘 뒤 최종 offset으로 한 번 더 맞춤
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: motionDuration(context, const Duration(milliseconds: 250)),
        ).then((_) {
          if (mounted) _onScroll();
        }),
      );
      return;
    }
    if (!_scroll.hasClients) return;
    final entries = _buildEntries();
    final entryIndex = entries.indexWhere(
      (e) => e is _MessageEntry && e.message.id == id,
    );
    if (entryIndex < 0) return;
    final listIndex = entries.length - 1 - entryIndex;
    _scroll.jumpTo(
      (listIndex * 76.0).clamp(0.0, _scroll.position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final built = _rowKeys[id]?.currentContext;
      if (built != null && mounted) {
        unawaited(
          Scrollable.ensureVisible(
            built,
            alignment: 0.4,
            duration: motionDuration(
              context,
              const Duration(milliseconds: 200),
            ),
          ).then((_) {
            if (mounted) _onScroll();
          }),
        );
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final show = _scroll.offset > 400;
    if (show != _showJump) setState(() => _showJump = show);
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
      return;
    }
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // PageUp·PageDown은 한 화면의 80%, Home은 가장 오래된 쪽(reverse라 목록 끝), End는 최신.
  // 지연 빌드라 끝 위치 추정이 늘어날 수 있어서 Home은 다음 프레임에 한 번 더 맞춤
  void _keyScroll(
    double Function(ScrollPosition p) target, {
    bool settle = false,
  }) {
    if (!_scroll.hasClients) return;
    _listFocus.requestFocus();
    void jump() {
      final p = _scroll.position;
      _scroll.jumpTo(target(p).clamp(p.minScrollExtent, p.maxScrollExtent));
    }

    jump();
    if (settle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) jump();
      });
    }
  }

  Map<ShortcutActivator, VoidCallback> get _scrollKeys => {
    const SingleActivator(LogicalKeyboardKey.pageUp): () =>
        _keyScroll((p) => p.pixels + p.viewportDimension * 0.8),
    const SingleActivator(LogicalKeyboardKey.pageDown): () =>
        _keyScroll((p) => p.pixels - p.viewportDimension * 0.8),
    const SingleActivator(LogicalKeyboardKey.home): () =>
        _keyScroll((p) => p.maxScrollExtent, settle: true),
    const SingleActivator(LogicalKeyboardKey.end): () => _keyScroll((_) => 0),
  };

  Widget _maybeHighlight(String id, Widget child) {
    if (id != widget.highlightMessageId && id != _flashId) return child;
    return ColoredBox(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) => _buildList(context);
}
