import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/room_member_list_dialog.dart';
import 'package:intragram/store/models.dart';

Conversation _room(Map<String, RoomMember> members) => Conversation(
  id: 'room1',
  peerAlias: 'room',
  peerPlatform: 'Room',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
  isRoom: true,
  members: members,
);

Future<String?> _open(
  WidgetTester tester,
  Conversation conversation, {
  TargetPlatform platform = TargetPlatform.android,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler, viewInsets: viewInsets),
          child: Builder(
            builder: (innerContext) => ElevatedButton(
              onPressed: () async {
                result = await showRoomMemberListDialog(
                  innerContext,
                  conversation,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  final members = <String, RoomMember>{
    'alice-id': const RoomMember(
      alias: 'alice',
      localVerified: true,
      peerVerified: true,
    ),
    'bob-id': const RoomMember(alias: 'bob', online: false),
  };

  for (final platform in TargetPlatform.values) {
    testWidgets(
      'renders member rows without a Material-ancestor crash on $platform',
      (tester) async {
        await _open(tester, _room(members), platform: platform);

        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(ListTile, 'alice'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'bob'), findsOneWidget);
      },
    );
  }

  testWidgets('shows a translated empty state for a room with no members', (
    tester,
  ) async {
    await _open(tester, _room(const {}));

    expect(tester.takeException(), isNull);
    expect(find.text('No one here yet'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('an offline member cannot be selected; an online one can', (
    tester,
  ) async {
    String? result;
    var resolved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showRoomMemberListDialog(context, _room(members));
              resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'bob')); // 오프라인
    await tester.pump();
    expect(resolved, isFalse, reason: 'offline row must not be selectable');

    await tester.tap(find.widgetWithText(ListTile, 'alice')); // 온라인
    await tester.pumpAndSettle();
    expect(resolved, isTrue);
    expect(result, 'alice-id');
  });

  testWidgets('scales row height with a large textScaler without throwing', (
    tester,
  ) async {
    await _open(tester, _room(members), textScaler: const TextScaler.linear(3));

    expect(tester.takeException(), isNull);
    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets(
    'keeps a bounded, non-negative viewport when the keyboard covers most of the screen',
    (tester) async {
      await _open(
        tester,
        _room(members),
        viewInsets: const EdgeInsets.only(bottom: 560),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
