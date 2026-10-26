import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/windows_clipboard.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/press_scale.dart';
import 'package:intragram/widgets/readable_list.dart';
import 'voice_recorder.dart';

part 'chat_input/clipboard.dart';
part 'chat_input/compose.dart';
part 'chat_input/action_bar.dart';

// Enter 전송, Shift+Enter 줄바꿈 (데스크톱/하드웨어 키보드). 터치 키보드는 "전송" 액션 사용
class ChatInput extends StatefulWidget {
  const ChatInput({
    required this.enabled,
    required this.onSend,
    required this.onAttach,
    required this.onTypingChanged,
    this.onSendImage,
    this.onAttachPaths,
    this.onSendVoice,
    this.replyPreview,
    this.onCancelReply,
    super.key,
  });

  final bool enabled;
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;
  final ValueChanged<bool> onTypingChanged;

  // null이면 이미지 붙여넣기 버튼을 숨김
  final ValueChanged<Uint8List>? onSendImage;

  // null이면 파일 붙여넣기 버튼을 숨김
  final ValueChanged<List<String>>? onAttachPaths;

  // 홀드 녹음이 끝나면 음성 바이트를 넘김. null이면 마이크 버튼을 숨김
  final ValueChanged<Uint8List>? onSendVoice;

  final String? replyPreview;
  final VoidCallback? onCancelReply;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

abstract class _ChatInputStateBase extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _typingSignalled = false;
  bool _hasClipboardText = false;
  bool _hasClipboardImage = false;
  bool _hasClipboardFiles = false;

  // 상대 스토어에도 자동 해제 타이머가 있지만(방어), 소스에서 stale 신호 자체를 안 보내려고 둠
  Timer? _typingIdle;
}

class _ChatInputState extends _ChatInputStateBase
    with
        WidgetsBindingObserver,
        _ChatInputClipboard,
        _ChatInputCompose,
        _ChatInputActionBar {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChange);
    _refreshClipboard();
  }

  @override
  void dispose() {
    _typingIdle?.cancel();
    _typingRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 포커스 얻을 때만 확인하면 다른 앱에서 복사하고 돌아와도 클립보드 퀵 버튼이
    // 옛 상태로 남아서 resumed에서도 다시 확인함
    if (state == AppLifecycleState.resumed) _refreshClipboard();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) _refreshClipboard();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        // 띠(배경·윗선)는 전폭, 입력 줄은 말풍선과 같은 가운데 열
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 200),
                  ),
                  child: widget.replyPreview != null
                      ? _replyStrip(scheme)
                      : const SizedBox.shrink(),
                ),
                _actionBar(scheme, s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
