part of '../chat_input.dart';

mixin _ChatInputCompose on _ChatInputStateBase {
  // 계속 입력 중이면 이 주기로 true를 다시 보냄. 수신 쪽 표시에 자체 backstop 타임아웃이 있어서
  // 다시 보내지 않으면 계속 타이핑해도 "입력 중" 점이 먼저 꺼짐
  Timer? _typingRefresh;

  void _onChanged(String value) {
    final typing = value.trim().isNotEmpty;
    if (typing != _typingSignalled) {
      _typingSignalled = typing;
      widget.onTypingChanged(typing);
      _typingRefresh?.cancel();
      _typingRefresh = typing
          ? Timer.periodic(const Duration(seconds: 2), (_) {
              if (mounted && _typingSignalled) widget.onTypingChanged(true);
            })
          : null;
    }
    _typingIdle?.cancel();
    if (typing) {
      _typingIdle = Timer(const Duration(seconds: 4), () {
        if (!mounted || !_typingSignalled) return;
        _typingSignalled = false;
        widget.onTypingChanged(false);
        _typingRefresh?.cancel();
        _typingRefresh = null;
      });
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    AppHaptics.lightImpact();
    widget.onSend(text);
    _controller.clear();
    _typingIdle?.cancel();
    _typingRefresh?.cancel();
    _typingRefresh = null;
    _typingSignalled = false;
    widget.onTypingChanged(false);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored; // 줄바꿈은 통과시킴
    }
    final composing = _controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      // 한국어 등 조합형 입력기가 조합 중이면 이 Enter는 조합 확정용이라 IME에 넘김
      // (안 그러면 확정 전 텍스트가 그대로 전송됨)
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }
}
