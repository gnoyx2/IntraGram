import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/open_chat.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/adaptive_layout.dart';

import '_harness.dart';

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

// 전환은 600ms 안에 끝남. 시스템 뒤로는 대화 창의 Navigator를 거쳐 한 프레임 늦게 시작해서 한 번 더 돌림
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<Harness> _home(
  WidgetTester tester,
  Size size, {
  List<DisplayFeature> features = const [],
}) async {
  _size(tester, size);
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1'))
    ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(displayFeatures: features),
        child: child!,
      ),
    ),
  );
  await _settle(tester);
  return h;
}

DisplayFeature _fold(double x, double height, DisplayFeatureState state) =>
    DisplayFeature(
      bounds: Rect.fromLTWH(x, 0, 0, height),
      type: DisplayFeatureType.fold,
      state: state,
    );

void main() {
  testWidgets('Duo fold and unfold preserve the chat state and draft', (
    tester,
  ) async {
    await _home(tester, const Size(466, 678));
    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'draft');
    final state = tester.state(find.byType(ChatRoomScreen));
    expect(find.byType(ConversationTile), findsNothing);

    _size(tester, const Size(890, 626));
    await _settle(tester);
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(find.text('draft'), findsOneWidget);
    expect(tester.state(find.byType(ChatRoomScreen)), same(state));
    expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, 361);

    _size(tester, const Size(466, 678));
    await _settle(tester);
    expect(find.byType(ConversationTile), findsNothing);
    expect(find.text('draft'), findsOneWidget);
    expect(tester.state(find.byType(ChatRoomScreen)), same(state));
    expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, 0);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a separating vertical hinge overrides the width breakpoint', (
    tester,
  ) async {
    await _home(
      tester,
      const Size(700, 840),
      features: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(340, 0, 20, 840),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    );
    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    expect(
      tester.getRect(find.byType(ConversationTile)).right,
      lessThanOrEqualTo(340),
    );
    expect(
      tester.getRect(find.byType(ChatRoomScreen)),
      const Rect.fromLTWH(360, 0, 340, 840),
    );
    final media = MediaQuery.of(tester.element(find.byType(ChatRoomScreen)));
    expect(media.size, const Size(340, 840));
    expect(media.displayFeatures, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // 평평하게 편 북타입 폴드도 반쯤 접은 것도 접힘선에서 나누고, 폭 0 접힘선엔 1pt 구분선을 둠
  for (final state in [
    DisplayFeatureState.postureFlat,
    DisplayFeatureState.postureHalfOpened,
  ]) {
    testWidgets('a zero-width ${state.name} fold separates panes', (
      tester,
    ) async {
      await _home(
        tester,
        const Size(626, 890),
        features: [_fold(313, 890, state)],
      );
      await tester.tap(find.byType(ConversationTile));
      await _settle(tester);
      expect(
        tester.getRect(find.byType(ConversationTile)).right,
        lessThanOrEqualTo(313),
      );
      expect(tester.getRect(find.byType(VerticalDivider)).left, 313);
      expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, 314);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a cutout or a fold near the edge keeps one pane', (
    tester,
  ) async {
    for (final feature in [
      const DisplayFeature(
        bounds: Rect.fromLTWH(350, 0, 20, 840),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
      // 접힘선에 걸친 작은 자유형 창: 한쪽이 kMinPaneWidth보다 좁음
      _fold(200, 840, DisplayFeatureState.postureFlat),
    ]) {
      await _home(tester, const Size(700, 840), features: [feature]);
      expect(find.text('No chat open'), findsNothing);
      expect(verticalHinge(tester.element(find.byType(HomeScreen))), isNull);
    }
  });

  testWidgets('an unfolded iPhone splits at the center; covers and iPads not', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      for (final (size, pad, split) in [
        (const Size(626, 890), false, true),
        (const Size(466, 678), false, false),
        (const Size(626, 890), true, false),
      ]) {
        OsPrivacy.cachedIsPad = pad;
        await _home(tester, size);
        expect(
          find.text('No chat open'),
          split ? findsOneWidget : findsNothing,
        );
        if (!split) continue;
        await tester.tap(find.byType(ConversationTile));
        await _settle(tester);
        expect(find.byType(ConversationTile), findsOneWidget);
        expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, 314);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      OsPrivacy.cachedIsPad = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('all narrow chat entry points share the adaptive navigator', (
    tester,
  ) async {
    await _home(tester, const Size(600, 800));
    final context = tester.element(find.byType(HomeScreen));
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await _settle(tester);
    pushChat(navigator, 'c1');
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    _size(tester, const Size(1280, 800));
    await _settle(tester);
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
