import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_commands.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

// 앱처럼 루트에 AppCommands를 두고 대화 하나를 띄움
Future<void> _openChat(WidgetTester tester, Size size) async {
  _setSize(tester, size);
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1'))
    ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      navigatorKey: key,
      builder: (context, child) => AppCommands(
        navigatorKey: key,
        unlocked: true,
        onNewConnection: (_) {},
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byType(ConversationTile));
}

Future<void> _backGesture(WidgetTester tester, String method, [double? x]) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, <String, Object?>{
          'touchOffset': <double>[x ?? 0, 400],
          'progress': (x ?? 0) / 400,
          'swipeEdge': 0,
        }),
      ),
      (_) {},
    );

void main() {
  testWidgets('a narrow chat slides in over the list with the page route', (
    tester,
  ) async {
    await _openChat(tester, const Size(600, 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final route = ModalRoute.of(tester.element(find.byType(ChatRoomScreen)))!;
    expect(route, isA<PageRoute<void>>());
    expect(route.animation!.status, AnimationStatus.forward);
    // 들어오는 동안은 밑의 목록이 보이고, 다 들어오면 목록을 그리지 않되 상태는 남김
    expect(find.byType(ConversationTile), findsOneWidget);
    await _settle(tester);
    expect(route.animation!.status, AnimationStatus.completed);
    expect(find.byType(ConversationTile), findsNothing);
    expect(find.byType(ConversationTile, skipOffstage: false), findsOneWidget);
  });

  testWidgets('an iOS edge swipe reveals the list and closes the chat', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _openChat(tester, const Size(390, 844));
      await _settle(tester);
      expect(find.byType(ConversationTile), findsNothing);
      final gesture = await tester.startGesture(const Offset(5, 400));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(find.byType(ConversationTile), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, greaterThan(0));
      await gesture.up();
      await _settle(tester);
      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(find.byType(ConversationTile), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android predictive back shows the list and commits to it', (
    tester,
  ) async {
    await _openChat(tester, const Size(412, 915));
    await _settle(tester);
    await _backGesture(tester, 'startBackGesture');
    await _backGesture(tester, 'updateBackGestureProgress', 200);
    await tester.pump();
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    await _backGesture(tester, 'commitBackGesture');
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(ConversationTile), findsOneWidget);
  });

  // 2단은 목록에 초점, 좁은 창은 초점을 놓친 상태(대화를 연 직후 입력창 밖)에서도 닫힘
  testWidgets('Esc and Cmd+W close the pane chat wherever the focus is', (
    tester,
  ) async {
    for (final size in [const Size(1280, 800), const Size(412, 915)]) {
      for (final meta in [false, true]) {
        await _openChat(tester, size);
        await _settle(tester);
        if (size.width > 840) {
          Focus.of(
            tester.element(find.byType(ConversationTile)),
          ).requestFocus();
        } else {
          primaryFocus?.unfocus();
        }
        await tester.pump();
        final focused = primaryFocus?.context;
        expect(focused?.widget, isNot(isA<EditableText>()));
        if (size.width > 840) {
          expect(
            focused?.findAncestorWidgetOfExactType<ChatRoomScreen>(),
            isNull,
          );
        }
        if (meta) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await _settle(tester);
        expect(find.byType(ChatRoomScreen), findsNothing, reason: '$size');
        expect(find.byType(ConversationTile), findsOneWidget);
      }
    }
  });

  // 앱 루트에 뜬 대화상자·화면이 먼저 닫혀야 함: 대화 창 Navigator는 맨 위를 따로 세서 밑의 대화가 닫혔었음
  for (final size in [const Size(412, 915), const Size(1280, 800)]) {
    testWidgets('predictive back closes what is above the chat at $size', (
      tester,
    ) async {
      await _openChat(tester, size);
      await _settle(tester);
      Future<void> back() async {
        await _backGesture(tester, 'startBackGesture');
        await _backGesture(tester, 'updateBackGestureProgress', 200);
        await tester.pump();
        await _backGesture(tester, 'commitBackGesture');
        await _settle(tester);
      }

      for (final open in <void Function(BuildContext)>[
        (c) => showDialog<void>(
          context: c,
          builder: (_) => const AlertDialog(content: Text('on top')),
        ),
        (c) => Navigator.of(c, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('on top')),
          ),
        ),
      ]) {
        open(tester.element(find.byType(ChatRoomScreen)));
        await _settle(tester);
        expect(find.text('on top'), findsOneWidget);
        await back();
        expect(find.text('on top'), findsNothing);
        expect(find.byType(ChatRoomScreen), findsOneWidget);
      }
      await back();
      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(find.byType(ConversationTile), findsOneWidget);
    });
  }

  testWidgets('screen readers keep the list beside the pane, not under it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openChat(tester, const Size(1280, 800));
    await _settle(tester);
    final list = find.bySemanticsLabel(RegExp('1 active chat'));
    expect(list, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('hi')), findsWidgets);
    // 좁은 창에선 대화가 목록을 덮어서 목록은 읽지 않음
    _setSize(tester, const Size(600, 800));
    await _settle(tester);
    expect(list, findsNothing);
    expect(find.bySemanticsLabel(RegExp('hi')), findsWidgets);
    semantics.dispose();
  });
}
