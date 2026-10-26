import 'package:flutter/material.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reduce motion이면 무한 반복 애니메이션을 아예 안 돌림 (배터리, 어지럼증)
    if (MediaQuery.of(context).disableAnimations) {
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
    final chat = context.chat;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        // 상대 말풍선과 같은 테두리·그림자·꼬리를 써서 밝은 배경에서도 윤곽이 보임
        decoration: bubbleDecoration(
          chat: chat,
          scheme: Theme.of(context).colorScheme,
          mine: false,
          joinsPrevious: false,
          joinsNext: false,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              reduceMotion
                  ? _staticDot(chat.onBubbleTheirs)
                  : _dot(i, chat.onBubbleTheirs),
          ],
        ),
      ),
    );
  }

  Widget _staticDot(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  // 점마다 0.2주기씩 밀린 삼각파로 통통 튐 (진짜 스프링은 아니지만 충분하고 의존성이 안 늚)
  Widget _dot(int index, Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value - index * 0.2) % 1.0;
        final bounce = t < 0.5 ? t * 2 : (1 - t) * 2;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Transform.translate(
            offset: Offset(0, -4 * bounce),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
