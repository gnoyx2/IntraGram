import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/features/chat/widgets/message_list.dart';
import 'package:intragram/features/chat/widgets/typing_dots.dart';

class DelayedCapture implements VoiceCapture {
  final stopped = Completer<Uint8List?>();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List?> finish() => stopped.future;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

void main() {
  testWidgets('finish after disposal must not deliver voice', (tester) async {
    final capture = DelayedCapture();
    var delivered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VoiceRecorderButton(
              enabled: true,
              createCapture: () => capture,
              onRecorded: (_) => delivered++,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecorderButton)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 750)),
    );
    await gesture.up();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    capture.stopped.complete(Uint8List.fromList(List.filled(4096, 7)));
    await tester.pump();
    await tester.pump();
    expect(delivered, 0);
  });

  testWidgets('recording banner controls must remain on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final alignment in [Alignment.bottomLeft, Alignment.bottomRight]) {
      final capture = DelayedCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: alignment,
              child: VoiceRecorderButton(
                enabled: true,
                createCapture: () => capture,
                onRecorded: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(VoiceRecorderButton));
      await tester.pump();
      await tester.pump();
      final bubble = tester.getRect(find.byType(AnimatedContainer).first);
      final send = tester.getRect(find.byIcon(Icons.check_circle));
      for (final rect in [bubble, send]) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('empty room must still show active typing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MessageList(messages: [], peerTyping: true)),
      ),
    );
    expect(find.byType(TypingDots), findsOneWidget);
  });
}
