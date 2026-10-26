import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/display_regions.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/adaptive_layout.dart';

import '_harness.dart';

class _LockedAccess extends VaultAccessNotifier {
  @override
  VaultAccessState build() => const VaultLocked();
}

Map<String, Object> _message(int status, List<List<num>> regions) => {
  'status': status,
  'regions': regions,
};

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

// 앱 루트처럼 OS가 알려 준 접힘선을 MediaQuery에 넣고 홈을 띄움
Future<void> _home(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store.upsertConversation(conv('c1'));
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(displayFeatures: DisplayRegions.features.value),
        child: child!,
      ),
    ),
  );
  await _settle(tester);
}

// 플랫폼 디버그 값은 테스트 본문 안에서 되돌려야 함 (tearDown은 검사 뒤에 돎)
Future<void> _onIOS(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  tearDown(() {
    DisplayRegions.features.value = null;
    OsPrivacy.cachedIsPad = null;
  });

  test('regions map to folds with the hinge posture', () {
    final half = DisplayRegions.parse(
      _message(2, [
        [445, 0, 24, 626, 1],
        [0, 300, 890, 0, 0],
      ]),
    )!;
    expect(half.map((f) => f.bounds), [
      const Rect.fromLTWH(445, 0, 24, 626),
      const Rect.fromLTWH(0, 300, 890, 0),
    ]);
    expect(half.every((f) => f.type == DisplayFeatureType.fold), isTrue);
    // 반쯤 접힌 활성 접힘선, 평평하게 편(비활성) 접힘선
    expect(half.map((f) => f.state), [
      DisplayFeatureState.postureHalfOpened,
      DisplayFeatureState.postureFlat,
    ]);
    expect(
      DisplayRegions.parse(
        _message(3, [
          [445, 0, 0, 626, 1],
        ]),
      )!.single.state,
      DisplayFeatureState.postureFlat,
    );
    expect(
      DisplayRegions.parse(
        _message(0, [
          [445, 0, 0, 626, 1],
        ]),
      )!.single.state,
      DisplayFeatureState.unknown,
    );
  });

  test('malformed messages mean the OS reports nothing', () {
    expect(DisplayRegions.parse(null), isNull);
    expect(DisplayRegions.parse('regions'), isNull);
    expect(DisplayRegions.parse({'status': 2}), isNull);
    // 지원하지만 접힘선이 없음 (커버 화면·보통 iPhone)
    expect(DisplayRegions.parse(_message(1, [])), isEmpty);
    expect(
      DisplayRegions.parse({
        'status': 2,
        'regions': [
          [445, 0, 0],
          [445, 0, -1, 626, 1],
          [double.nan, 0, 0, 626, 1],
          ['445', 0, 0, 626, 1],
        ],
      }),
      isEmpty,
    );
  });

  testWidgets('the app root puts reported folds into MediaQuery', (
    tester,
  ) async {
    await _onIOS(() async {
      final h = Harness();
      addTearDown(h.dispose);
      mockPrivacyChannel([]);
      await tester.pumpWidget(
        h.wrap(
          const IntraGramApp(),
          overrides: [
            vaultAccessProvider.overrideWith(_LockedAccess.new),
            notificationBridgeProvider.overrideWith((ref) {}),
            roomHintBridgeProvider.overrideWith((ref) {}),
            screenshotBridgeProvider.overrideWith((ref) {}),
          ],
        ),
      );
      await tester.pump();
      List<DisplayFeature> features() => MediaQuery.displayFeaturesOf(
        tester.element(find.byType(PinGateScreen)),
      );
      expect(features(), isEmpty);
      Future<void> send(Object? arguments) => TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            'intragram/privacy',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onDisplayRegions', arguments),
            ),
            (_) {},
          );
      await send(
        _message(2, [
          [400, 0, 0, 800, 1],
        ]),
      );
      await tester.pump();
      expect(features().single.bounds, const Rect.fromLTWH(400, 0, 0, 800));
      expect(features().single.state, DisplayFeatureState.postureHalfOpened);
      await send(_message(1, []));
      await tester.pump();
      expect(features(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a reported crease splits the panes and replaces the guess', (
    tester,
  ) async {
    await _onIOS(() async {
      OsPrivacy.cachedIsPad = false;
      // 가로로 편 내부 화면 가운데의 세로 접힘선 (OS가 여백 24pt를 함께 알려 줌)
      DisplayRegions.update(
        _message(3, [
          [433, 0, 24, 626, 0],
        ]),
      );
      await _home(tester, const Size(890, 626));
      await tester.tap(find.byType(ConversationTile));
      await _settle(tester);
      expect(tester.getRect(find.byType(ConversationTile)).right, 433);
      expect(tester.getTopLeft(find.byType(ChatRoomScreen)).dx, 457);
      // 접힘선 여백은 바탕색으로 칠하고 가운데 구분선
      expect(tester.getRect(find.byType(VerticalDivider)).center.dx, 445);

      // OS가 알려 주는 iOS에선 세로로 편 화면을 가운데로 짐작해 나누지 않음
      DisplayRegions.update(_message(3, []));
      expect(phoneCrease(const Size(626, 890)), isNull);
      DisplayRegions.features.value = null;
      expect(phoneCrease(const Size(626, 890)), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a half-open horizontal crease turns on tabletop layouts', (
    tester,
  ) async {
    await _onIOS(() async {
      DisplayRegions.update(
        _message(2, [
          [0, 445, 626, 0, 1],
        ]),
      );
      await _home(tester, const Size(626, 890));
      final fold = tabletopFold(tester.element(find.byType(HomeScreen)));
      expect(fold?.bounds, const Rect.fromLTWH(0, 445, 626, 0));
      expect(verticalHinge(tester.element(find.byType(HomeScreen))), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
