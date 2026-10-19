import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette._();

  // 브랜드 액센트. 작은 글씨는 AAA 대비를 위해 ChatColors.accentInk를 씀
  static const Color accentLight = Color(0xFF2563EB);
  static const Color accentDark = Color(0xFF60A5FA);

  static const Color scaffoldLight = Color(0xFFFFFFFF);
  static const Color chatCanvasLight = Color(0xFFF6F8FA);
  static const Color bubbleMineTopLight = Color(0xFFF0F5FF);
  static const Color bubbleMineLight = Color(0xFFDCE7FD);
  // 그라디언트 밝은 끝이 캔버스와 1.03:1이라 0.5dp 윤곽으로 1.25:1 이상 갈라 줌
  static const Color bubbleMineEdgeLight = Color(0xFFC9D8F6);
  static const Color bubbleTheirsLight = Color(0xFFFFFFFF);
  // 에메랄드 #10B981은 흰 배경 아이콘 대비가 3:1에 못 미쳐 한 단계 진하게 씀
  static const Color onlineLight = Color(0xFF059669);
  static const Color burnLight = Color(0xFF86290C);

  static const Color scaffoldDark = Color(0xFF0D0F14);
  static const Color chatCanvasDark = Color(0xFF080A0D);
  static const Color bubbleMineTopDark = Color(0xFF213F6B);
  static const Color bubbleMineDark = Color(0xFF172C4B);
  static const Color bubbleTheirsDark = Color(0xFF141820);
  static const Color onlineDark = Color(0xFF34D399);
  static const Color burnDark = Color(0xFFFFCCB4);
}

@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.canvas,
    required this.bubbleMineTop,
    required this.bubbleMine,
    required this.bubbleMineEdge,
    required this.bubbleTheirs,
    required this.onBubbleMine,
    required this.onBubbleTheirs,
    required this.online,
    required this.burn,
    required this.accentInk,
    required this.bubbleShadow,
  });

  final Color canvas;
  // 내 말풍선은 bubbleMineTop에서 bubbleMine으로 흐르는 그라디언트
  final Color bubbleMineTop;
  final Color bubbleMine;
  // 내 말풍선 윤곽. 다크는 바탕이 이미 캔버스와 갈라져서 투명
  final Color bubbleMineEdge;
  final Color bubbleTheirs;
  final Color onBubbleMine;
  final Color onBubbleTheirs;
  final Color online;
  final Color burn;
  // 발신자 이름·링크·읽음 카운트처럼 작은 액센트 글씨용. 양쪽 테마 모두 7:1 이상
  final Color accentInk;
  // 다크 모드에선 그림자가 안 보이므로 투명 (별도 다크 분기 없이 이 필드로 흡수)
  final Color bubbleShadow;

  static const ChatColors light = ChatColors(
    canvas: AppPalette.chatCanvasLight,
    bubbleMineTop: AppPalette.bubbleMineTopLight,
    bubbleMine: AppPalette.bubbleMineLight,
    bubbleMineEdge: AppPalette.bubbleMineEdgeLight,
    bubbleTheirs: AppPalette.bubbleTheirsLight,
    onBubbleMine: Color(0xFF13233D),
    onBubbleTheirs: Color(0xFF171C26),
    online: AppPalette.onlineLight,
    burn: AppPalette.burnLight,
    accentInk: Color(0xFF1E40AF),
    bubbleShadow: Color(0x140F172A),
  );

  static const ChatColors dark = ChatColors(
    canvas: AppPalette.chatCanvasDark,
    bubbleMineTop: AppPalette.bubbleMineTopDark,
    bubbleMine: AppPalette.bubbleMineDark,
    bubbleMineEdge: Color(0x00000000),
    bubbleTheirs: AppPalette.bubbleTheirsDark,
    onBubbleMine: Color(0xFFF1F5FC),
    onBubbleTheirs: Color(0xFFF1F5FC),
    online: AppPalette.onlineDark,
    burn: AppPalette.burnDark,
    accentInk: Color(0xFFBFDBFE),
    bubbleShadow: Color(0x00000000),
  );

  @override
  ChatColors copyWith({
    Color? canvas,
    Color? bubbleMineTop,
    Color? bubbleMine,
    Color? bubbleMineEdge,
    Color? bubbleTheirs,
    Color? onBubbleMine,
    Color? onBubbleTheirs,
    Color? online,
    Color? burn,
    Color? accentInk,
    Color? bubbleShadow,
  }) {
    return ChatColors(
      canvas: canvas ?? this.canvas,
      bubbleMineTop: bubbleMineTop ?? this.bubbleMineTop,
      bubbleMine: bubbleMine ?? this.bubbleMine,
      bubbleMineEdge: bubbleMineEdge ?? this.bubbleMineEdge,
      bubbleTheirs: bubbleTheirs ?? this.bubbleTheirs,
      onBubbleMine: onBubbleMine ?? this.onBubbleMine,
      onBubbleTheirs: onBubbleTheirs ?? this.onBubbleTheirs,
      online: online ?? this.online,
      burn: burn ?? this.burn,
      accentInk: accentInk ?? this.accentInk,
      bubbleShadow: bubbleShadow ?? this.bubbleShadow,
    );
  }

  @override
  ChatColors lerp(ChatColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return ChatColors(
      canvas: mix(canvas, other.canvas),
      bubbleMineTop: mix(bubbleMineTop, other.bubbleMineTop),
      bubbleMine: mix(bubbleMine, other.bubbleMine),
      bubbleMineEdge: mix(bubbleMineEdge, other.bubbleMineEdge),
      bubbleTheirs: mix(bubbleTheirs, other.bubbleTheirs),
      onBubbleMine: mix(onBubbleMine, other.onBubbleMine),
      onBubbleTheirs: mix(onBubbleTheirs, other.onBubbleTheirs),
      online: mix(online, other.online),
      burn: mix(burn, other.burn),
      accentInk: mix(accentInk, other.accentInk),
      bubbleShadow: mix(bubbleShadow, other.bubbleShadow),
    );
  }
}

extension ChatColorsX on BuildContext {
  ChatColors get chat =>
      Theme.of(this).extension<ChatColors>() ?? ChatColors.light;
}
