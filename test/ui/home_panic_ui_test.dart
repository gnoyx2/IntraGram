import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/network/server_controller.dart';

import '../support/panic_fakes.dart';
import '_harness.dart';

// 패닉 단계는 모두 Completer/fake로 제어해 위젯 FakeAsync에서 검증함
Future<({Harness h, PanicSteps steps})> _pumpHomeWithPanicFakes(
  WidgetTester tester,
) async {
  final steps = PanicSteps();
  mockDirectorySettings();
  final h = Harness(
    identityStore: const PanicIdentityStore(),
    registryBuilder: (store, identity) =>
        PanicRegistry(steps, store: store, identity: identity),
  );
  // fake zone의 Completer를 teardown의 진짜 zone에서 기다리지 않음
  addTearDown(() {
    steps.completeAll();
    h.store.dispose();
  });
  h.store.upsertConversation(conv('c1'));
  const fileSourceChannel = MethodChannel('intragram/file_source');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(fileSourceChannel, (call) async {
    steps.calls.add('native');
    await steps.native.future;
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(fileSourceChannel, null),
  );
  mockPrivacyChannel(steps.calls);
  Future<void> voiceStopper() {
    steps.calls.add('voice');
    return steps.voice.future;
  }

  VoiceProducerRegistry.instance.register(voiceStopper);
  addTearDown(() => VoiceProducerRegistry.instance.unregister(voiceStopper));

  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      overrides: [
        vaultProvider.overrideWithValue(PanicVault()),
        notificationServiceProvider.overrideWithValue(
          PanicNotifications(steps),
        ),
        foregroundServiceProvider.overrideWithValue(PanicForeground(steps)),
        serverControllerProvider.overrideWith(() => PanicServer(steps)),
      ],
    ),
  );
  await tester.pump();
  return (h: h, steps: steps);
}

// 오버플로 메뉴 → 긴급 소거 → 확인 다이얼로그의 "Wipe"까지 누름. 확인 버튼
// 탭 직후 pump 한 번으로 콜백(패닉 시퀀스)을 시작시킴: 이게 없으면 다이얼로그
// future의 continuation이 안 돌아서 패닉이 아예 시작도 안 함
Future<void> _confirmPanic(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byIcon(Icons.delete_forever));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Wipe everything now?'), findsOneWidget);

  await tester.tap(find.widgetWithText(FilledButton, 'Wipe'));
  await tester.pump();
}

void main() {
  testWidgets('panic wipe asks for confirmation then clears the store', (
    tester,
  ) async {
    final (:h, :steps) = await _pumpHomeWithPanicFakes(tester);

    await _confirmPanic(tester);

    // 정지 단계 다섯 개가 동시에 시작됨: 소각(store.secureWipe)은 아직 안 함
    expect(
      steps.calls,
      unorderedEquals([
        'voice',
        'notifications',
        'foreground',
        'server',
        'links',
      ]),
    );
    expect(h.store.conversations, isNotEmpty);

    steps.completeAllExceptLinks();
    await tester.pump();
    expect(h.store.conversations, isNotEmpty, reason: 'links still stopping');

    steps.links.complete();
    await tester.pump();
    expect(steps.calls.last, 'native', reason: 'native release follows drain');
    expect(h.store.conversations, isNotEmpty);

    steps.native.complete();
    await pumpUntil(
      tester,
      () => find.text('Memory wiped.').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.store.conversations, isEmpty);
    expect(find.text('Wipe everything now?'), findsNothing); // 다이얼로그 닫힘
    expect(find.text('Memory wiped.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panic wipe reports a hung stop step as a partial failure', (
    tester,
  ) async {
    final (:h, :steps) = await _pumpHomeWithPanicFakes(tester);

    await _confirmPanic(tester);
    // 음성 producer만 안 끝남: 나머지는 정상 종료
    steps.notifications.complete();
    steps.foreground.complete(true);
    steps.server.complete();
    steps.links.complete();
    steps.native.complete();
    await tester.pump();
    expect(h.store.conversations, isNotEmpty, reason: 'still waiting on voice');

    // kPanicStepTimeout(5초)이 지나면 성공으로 치지 않고 부분 실패로 넘어가
    // 소각은 그대로 진행함
    await tester.pump(const Duration(seconds: 6));
    await pumpUntil(tester, () => h.store.conversations.isEmpty);
    await pumpUntil(
      tester,
      () => find.textContaining('did not stop in time').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.store.conversations, isEmpty);
    expect(find.textContaining('did not stop in time'), findsOneWidget);
    expect(find.text('Memory wiped.'), findsNothing);

    // 뒤늦게 음성 정지가 끝나도 새 세션은 그대로
    h.store.upsertConversation(conv('fresh'));
    steps.voice.complete();
    await tester.pump();
    expect(h.store.conversations.map((c) => c.id), ['fresh']);
    expect(h.store.messages('fresh'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
