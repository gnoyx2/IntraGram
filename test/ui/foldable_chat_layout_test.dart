import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:intragram/features/chat/chat_input.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/features/chat/widgets/message_list.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Future<ValueNotifier<List<DisplayFeature>>> _open(WidgetTester tester) async {
  _size(tester, const Size(600, 800));
  // 실제 폰처럼 상태 표시줄을 둠: Scaffold 본문 안에선 위 여백이 지워져서 접힘선 기준점이 그만큼 어긋났었음
  tester.view.padding = const FakeViewPadding(top: 40);
  tester.view.viewPadding = const FakeViewPadding(top: 40);
  addTearDown(tester.view.reset);
  final features = ValueNotifier<List<DisplayFeature>>([]);
  addTearDown(features.dispose);
  final h = Harness();
  addTearDown(h.dispose);
  h.store.upsertConversation(conv('c1'));
  for (var i = 0; i < 60; i++) {
    h.store.addMessage(
      msg(id: '$i', dir: MessageDirection.incoming, text: 'message $i'),
    );
  }
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: features,
        builder: (context, features, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(displayFeatures: features),
          child: child!,
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.byType(ConversationTile));
  await _settle(tester);
  return features;
}

void main() {
  for (final type in [DisplayFeatureType.fold, DisplayFeatureType.hinge]) {
    testWidgets('tabletop $type keeps messages and input off the crease', (
      tester,
    ) async {
      final features = await _open(tester);
      await tester.enterText(find.byType(TextField), 'draft');
      final inputState = tester.state(find.byType(ChatInput));
      final messageState = tester.state(find.byType(MessageList));
      final crease = Rect.fromLTWH(
        0,
        390,
        600,
        type == DisplayFeatureType.fold ? 0 : 20,
      );
      features.value = [
        DisplayFeature(
          bounds: crease,
          type: type,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      await _settle(tester);
      expect(
        tester.getRect(find.byType(MessageList)).bottom,
        lessThanOrEqualTo(crease.top),
      );
      expect(
        tester.getRect(find.byType(ChatInput)).top,
        greaterThanOrEqualTo(crease.bottom),
      );
      expect(tester.state(find.byType(ChatInput)), same(inputState));
      expect(tester.state(find.byType(MessageList)), same(messageState));

      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      await _settle(tester);
      expect(
        tester.getRect(find.byType(ChatInput)).bottom,
        lessThanOrEqualTo(crease.top),
      );
      expect(find.text('draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folding preserves scrolled history and an active recording', (
    tester,
  ) async {
    final previous = RecordPlatform.instance;
    final recorder = _Recorder();
    RecordPlatform.instance = recorder;
    addTearDown(() => RecordPlatform.instance = previous);
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'unfinished draft');
    final scroll = tester
        .widget<ListView>(
          find.descendant(
            of: find.byType(MessageList),
            matching: find.byType(ListView),
          ),
        )
        .controller!;
    scroll.jumpTo(500);
    await tester.tap(find.byType(VoiceRecorderButton));
    await _settle(tester);
    final voiceState = tester.state(find.byType(VoiceRecorderButton));
    expect(recorder.starts, 1);
    for (final size in [const Size(1280, 800), const Size(466, 678)]) {
      _size(tester, size);
      await _settle(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(tester.state(find.byType(VoiceRecorderButton)), same(voiceState));
      expect(recorder.starts, 1);
      expect(recorder.stops, 0);
      expect(scroll.offset, 500);
      expect(find.text('unfinished draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byType(VoiceRecorderButton));
    await _settle(tester);
    expect(recorder.stops, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact keyboard viewport scrolls a multiline composer', (
    tester,
  ) async {
    await _open(tester);
    _size(tester, const Size(320, 360));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 170);
    await tester.enterText(
      find.byType(TextField),
      'one\ntwo\nthree\nfour\nfive',
    );
    await _settle(tester);
    expect(find.byType(ChatInput), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 실제 플랫폼처럼 녹음 상태를 알려야 record 패키지가 정지 때 진폭 타이머를 멈춤
class _Recorder extends RecordPlatform {
  final pcm = StreamController<Uint8List>();
  final states = StreamController<RecordState>.broadcast();
  int starts = 0;
  int stops = 0;
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    starts++;
    states.add(RecordState.record);
    return pcm.stream;
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => states.stream;
  @override
  Future<bool> isRecording(String recorderId) async => starts > stops;
  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -45, max: 0);
  @override
  Future<String?> stop(String recorderId) async {
    stops++;
    states.add(RecordState.stop);
    await pcm.close();
    return null;
  }

  @override
  Future<void> dispose(String recorderId) => pcm.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
