import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/peer_avatar.dart';

import '../support/contrast.dart';

// 디자인 시스템의 대비 약속(본문·보조 글씨 7:1, 아이콘 3:1)을 색 값이 바뀌어도 지키게 고정함
void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    final scheme = theme.colorScheme;
    final chat = theme.extension<ChatColors>()!;
    final name = scheme.brightness.name;

    test('$name: text pairs stay at AAA', () {
      const meta = AppOpacity.secondaryText;
      final pairs = <String, (Color, Color)>{
        'onSurface': (scheme.onSurface, scheme.surface),
        'onSurfaceVariant': (scheme.onSurfaceVariant, scheme.surface),
        'onSurfaceVariant/highest': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
        'mine': (chat.onBubbleMine, chat.bubbleMine),
        'mine top': (chat.onBubbleMine, chat.bubbleMineTop),
        'theirs': (chat.onBubbleTheirs, chat.bubbleTheirs),
        'ink on theirs': (chat.accentInk, chat.bubbleTheirs),
        'ink on mine': (chat.accentInk, chat.bubbleMine),
        'ink on mine top': (chat.accentInk, chat.bubbleMineTop),
        'meta on mine': (
          chat.onBubbleMine.withValues(alpha: meta),
          chat.bubbleMine,
        ),
        'meta on mine top': (
          chat.onBubbleMine.withValues(alpha: meta),
          chat.bubbleMineTop,
        ),
        'meta on theirs': (
          chat.onBubbleTheirs.withValues(alpha: meta),
          chat.bubbleTheirs,
        ),
        'burn on mine': (chat.burn, chat.bubbleMine),
        'burn on mine top': (chat.burn, chat.bubbleMineTop),
        'tertiary': (scheme.tertiary, scheme.surface),
        'error': (scheme.error, scheme.surface),
        'error container': (scheme.onErrorContainer, scheme.errorContainer),
        'tooltip': (scheme.onInverseSurface, scheme.inverseSurface),
        'primary container': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'secondary container': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        for (final (level, surface) in [
          ('lowest', scheme.surfaceContainerLowest),
          ('low', scheme.surfaceContainerLow),
          ('container', scheme.surfaceContainer),
          ('high', scheme.surfaceContainerHigh),
        ])
          'secondary text/$level': (scheme.onSurfaceVariant, surface),
      };
      for (final MapEntry(key: label, value: (fg, bg)) in pairs.entries) {
        expect(contrastRatio(fg, bg), greaterThanOrEqualTo(7), reason: label);
      }
    });

    test('$name: status icons stay at 3:1', () {
      expect(contrastRatio(chat.online, scheme.surface), greaterThan(3));
      expect(contrastRatio(scheme.primary, chat.bubbleMine), greaterThan(3));
    });

    test('$name: bubble outlines stand off the canvas at 1.25:1', () {
      // 윤곽이 투명한 쪽은 바탕색 자체가 캔버스와 갈라져야 함
      double edge(Color line, Color fill) => math.max(
        contrastRatio(line, chat.canvas),
        contrastRatio(fill, chat.canvas),
      );
      for (final fill in [chat.bubbleMineTop, chat.bubbleMine]) {
        expect(edge(chat.bubbleMineEdge, fill), greaterThanOrEqualTo(1.25));
      }
      expect(
        edge(scheme.outlineVariant, chat.bubbleTheirs),
        greaterThanOrEqualTo(1.25),
      );
    });

    test('$name: every avatar duotone keeps its initials at AAA', () {
      final ink = scheme.brightness == Brightness.dark
          ? const Color(0xFFF1F5FC)
          : const Color(0xFF14233B);
      for (var i = 0; i < 400; i++) {
        final colors = PeerAvatar.gradientFor(
          'peer-$i',
          scheme.brightness,
        ).colors;
        final middle = Color.lerp(colors.first, colors.last, 0.5)!;
        expect(contrastRatio(ink, middle), greaterThanOrEqualTo(7));
      }
    });
  }

  // 비텍스트 대비 1.4.11: 입력창 경계·켜진 스위치 트랙·가만히 있는 스크롤바는 3:1.
  // 라이트 모드의 iOS·macOS 대화상자 버튼 글씨는 반투명 회색 바탕에서도 읽히게 surface 기준 7:1을 넘김
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    final scheme = theme.colorScheme;
    test('${scheme.brightness.name}: controls stand off the surface', () {
      final border = theme.inputDecorationTheme.enabledBorder!.borderSide;
      expect(contrastRatio(border.color, scheme.surface), greaterThan(3));
      expect(contrastRatio(scheme.primary, scheme.surface), greaterThan(3));
      final thumb = theme.scrollbarTheme.thumbColor!.resolve(const {})!;
      expect(contrastRatio(thumb, scheme.surface), greaterThan(3));
      if (scheme.brightness == Brightness.light) {
        final action = theme.cupertinoOverrideTheme!.primaryColor!;
        expect(contrastRatio(action, scheme.surface), greaterThan(7));
      }
    });
  }

  test('high contrast themes lift secondary text and outlines', () {
    for (final theme in [
      AppTheme.light(highContrast: true),
      AppTheme.dark(highContrast: true),
    ]) {
      final scheme = theme.colorScheme;
      expect(scheme.onSurfaceVariant, scheme.onSurface);
      expect(scheme.outlineVariant, scheme.outline);
    }
  });

  test('light mine bubbles draw the edge token', () {
    final theme = AppTheme.light();
    final chat = theme.extension<ChatColors>()!;
    ShapeDecoration mine(ChatColors colors) => bubbleDecoration(
      chat: colors,
      scheme: theme.colorScheme,
      mine: true,
      joinsPrevious: false,
      joinsNext: false,
    );
    expect(
      mine(chat),
      isNot(mine(chat.copyWith(bubbleMineEdge: Colors.transparent))),
    );
  });

  test('avatar colour and initials are stable per device', () {
    expect(PeerAvatar.hueFor('abc'), PeerAvatar.hueFor('abc'));
    expect(PeerAvatar.hueFor('abc'), inInclusiveRange(0, 359));
    expect(PeerAvatar.initialsFor('bob-owl-22'), 'BO');
    expect(PeerAvatar.initialsFor('  '), '?');
    expect(PeerAvatar.initialsFor('하늘 바다'), '하바');
  });

  testWidgets('an avatar with a platform reads the device to screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeerAvatar(peerId: 'p', alias: 'ann', platform: 'macOS'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('macOS device'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });
}
