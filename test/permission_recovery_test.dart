import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/widgets/scanner_view.dart';

// 권한을 거부한 사람에게 어디서 다시 켜는지 알려 주고, 열 수 있으면 설정 화면으로 바로 보냄
// (flutter_test의 기본 대상 플랫폼은 Android라 호스트와 상관없이 설정 열기가 있는 플랫폼으로 돎)
class _DeniedCapture implements VoiceCapture {
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List?> finish() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<double> get amplitudeStream => const Stream<double>.empty();
}

void main() {
  const en = S(AppLang.en);

  testWidgets('a denied microphone offers the settings page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VoiceRecorderButton(
              enabled: true,
              onRecorded: (_) {},
              createCapture: _DeniedCapture.new,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(VoiceRecorderButton));
    await tester.pump();
    await tester.pump();
    expect(find.text(en.t('voice.micPermission')), findsOneWidget);
    expect(find.text(en.t('settings.open')), findsOneWidget);
  });

  testWidgets('a denied camera explains the other way in and opens '
      'settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraUnavailable(
            text: en.t('scanScreen.noCamera'),
            denied: true,
          ),
        ),
      ),
    );
    expect(
      find.text('${en.t('scan.cameraDenied')} ${en.t('scanScreen.noCamera')}'),
      findsOneWidget,
    );
    expect(find.text(en.t('settings.open')), findsOneWidget);
  });

  testWidgets('a missing camera shows the other way in only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CameraUnavailable(text: en.t('sasScan.noCamera'))),
      ),
    );
    expect(find.text(en.t('sasScan.noCamera')), findsOneWidget);
    expect(find.text(en.t('settings.open')), findsNothing);
  });
}
