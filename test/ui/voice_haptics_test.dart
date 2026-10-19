import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/theme/app_theme.dart';

import '../support/contrast.dart';

class _Capture implements VoiceCapture {
  bool allowed = true;
  bool cancelled = false;
  bool finished = false;
  @override
  Future<bool> hasPermission() async => allowed;
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List?> finish() async {
    finished = true;
    return Uint8List(4096);
  }

  @override
  Future<void> cancel() async => cancelled = true;
  @override
  Future<void> dispose() async {}
  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

void main() {
  final calls = <Object?>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, _Capture capture, ThemeData theme) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: VoiceRecorderButton(
                enabled: true,
                onRecorded: (_) {},
                createCapture: () => capture,
              ),
            ),
          ),
        ),
      );

  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('${theme.brightness.name}: recording starts and cancels once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = _Capture();
      await pump(tester, capture, theme);
      await tester.tap(find.byType(VoiceRecorderButton));
      await tester.pump();
      await tester.pump();
      expect(calls, ['HapticFeedbackType.lightImpact']);
      final clock = tester.widget<Text>(find.text('0:00'));
      final banner = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('0:00'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(banner.duration, Duration.zero);
      expect(
        contrastRatio(
          clock.style!.color!,
          (banner.decoration! as BoxDecoration).color!,
        ),
        greaterThanOrEqualTo(7),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(VoiceRecorderButton));
      await tester.pumpAndSettle();
      expect(capture.cancelled, isTrue);
      expect(calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });
  }

  testWidgets('crossing the cancel threshold only haptics on transitions', (
    tester,
  ) async {
    final capture = _Capture();
    await pump(tester, capture, AppTheme.dark());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecorderButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -70));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    expect(calls, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(calls.last, 'HapticFeedbackType.selectionClick');
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(calls.last, 'HapticFeedbackType.mediumImpact');
    final count = calls.length;
    await gesture.up();
    await tester.pumpAndSettle();
    expect(capture.cancelled, isTrue);
    expect(calls, hasLength(count));
  });

  testWidgets('permission denial has no start haptic', (tester) async {
    final capture = _Capture()..allowed = false;
    await pump(tester, capture, AppTheme.light());
    await tester.tap(find.byType(VoiceRecorderButton));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('sending a valid recording gives one light completion haptic', (
    tester,
  ) async {
    final capture = _Capture();
    await pump(tester, capture, AppTheme.light());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecorderButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(capture.finished, isTrue);
    expect(capture.cancelled, isFalse);
    expect(calls, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });
}
