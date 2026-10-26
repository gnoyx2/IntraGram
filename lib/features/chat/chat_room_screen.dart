import 'dart:async';
import 'dart:io' show File;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:intragram/widgets/keyboard_access.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_navigator.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/app_providers/conversation_actions.dart';
import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/adaptive_layout.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/theme/type_scale.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/error_state.dart';
import 'package:intragram/widgets/picker_feedback.dart';
import 'chat_input.dart';
import 'widgets/add_people_sheet.dart';
import 'widgets/attach_sheet.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/drop_overlay.dart';
import 'widgets/message_list.dart';
import 'widgets/room_integrity_banner.dart';
import 'widgets/room_member_list_dialog.dart';
import 'widgets/sas_fingerprint_dialog.dart';

part 'chat_room/search.dart';
part 'chat_room/dialogs.dart';
part 'chat_room/drag_drop.dart';
part 'chat_room/scaffold.dart';
part 'chat_room/body.dart';
part 'chat_room/layout.dart';
part 'chat_room/skeleton.dart';
part 'chat_room/banners.dart';
part 'chat_room/announce.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

abstract class _ChatRoomScreenStateBase extends ConsumerState<ChatRoomScreen> {
  LinkRegistry get _registry => ref.read(linkRegistryProvider);
  bool _dragging = false;

  // 방을 연 순간의 안 읽은 개수. _markRead가 0으로 만들기 전에 잡아둠 ("New messages" 구분선 위치용)
  int _unreadOnOpen = 0;

  String? _replyingTo;

  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _hits = const <String>[];
  int _hitIndex = 0;

  void _markRead() {
    _registry.markRoomRead(widget.conversationId);
  }
}

class _ChatRoomScreenState extends _ChatRoomScreenStateBase
    with
        _ChatRoomSearch,
        _ChatRoomDialogs,
        _ChatRoomDragDrop,
        _ChatRoomScaffold,
        _ChatRoomBody,
        _ChatRoomAnnounce {
  @override
  void initState() {
    super.initState();
    _unreadOnOpen =
        ref
            .read(inMemoryStoreProvider)
            .conversation(widget.conversationId)
            ?.unread ??
        0;
    // 스크린샷 알림 대상. provider면 initState에서 못 건드려서 전역 변수
    foregroundConversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
    _startAnnouncing();
  }

  @override
  void dispose() {
    _stopAnnouncing();
    if (foregroundConversationId == widget.conversationId) {
      foregroundConversationId = null;
    }
    // 방을 나가면 디코드된 사진을 캐시에 남기지 않음 (하위 위젯은 이미 dispose됨)
    OsPrivacy.evictTrackedImages();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 앱바와 본문이 각자 conversation을 watch하니 여기선 대화가 있는지만 봄
    // online/peerTyping/secure 변화로 메시지 리스트까지 다시 도는 걸 막음
    final exists = ref.watch(
      conversationProvider(widget.conversationId).select((c) => c != null),
    );

    ref.listen(roomMessagesProvider(widget.conversationId), (_, _) {
      _markRead();
    });

    if (!exists) {
      final s = S.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(s.t('common.backToHome'))),
        body: EmptyState(
          art: EmptyStateArt.bubbles,
          title: s.t('empty.endedTitle'),
          body: s.t('empty.endedBody'),
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.t('common.backToHome')),
          ),
        ),
      );
    }

    final replyParent = _replyingTo == null
        ? null
        : ref.watch(
            messageByIdProvider((
              conversationId: widget.conversationId,
              messageId: _replyingTo!,
            )),
          );
    final replyPreview = _replyingTo == null
        ? null
        : replyParent == null
        ? S.of(context).t('common.message')
        : replyParent.kind == MessageKind.file
        ? S.of(context).t('common.file')
        : (replyParent.text ?? S.of(context).t('common.message'));

    final body = _body(replyPreview);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        // 파일 보내기. Esc·⌘W 닫기는 앱 루트(AppCommands)가 받고 검색 중이면 PopScope가 검색만 닫음
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _attach,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _attach,
      },
      child: Actions(
        actions: {
          SearchMessagesIntent: CallbackAction<SearchMessagesIntent>(
            onInvoke: (_) => _openSearch(),
          ),
        },
        child: Focus(autofocus: true, child: _popScopeScaffold(body)),
      ),
    );
  }

  // 나갈 때 묻는 건 없음 (보관 여부는 메뉴의 '이 기기에 보관'). 검색 중 뒤로는 검색만 닫음
  Widget _popScopeScaffold(Widget body) {
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: _ChatAppBarScope(
          toolbarHeight: AppType.toolbarHeight(context),
          conversationId: widget.conversationId,
          builder: _appBar,
        ),
        body: _isDesktop
            ? DropTarget(
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (detail) => _onDrop(detail.files),
                child: Stack(
                  children: [
                    body,
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _dragging ? 1 : 0,
                        duration: motionDuration(
                          context,
                          const Duration(milliseconds: 150),
                        ),
                        child: const DropOverlay(),
                      ),
                    ),
                  ],
                ),
              )
            : body,
      ),
    );
  }
}
