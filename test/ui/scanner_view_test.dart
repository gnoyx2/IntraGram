import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/peer_code.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/widgets/scanner_view.dart';

import '../support/fake_camera_platform.dart';
import '../support/qr_frames.dart';

// ML Kit 없는 스캐너의 카메라 수명: 프레임 속 코드를 넘기면 카메라를 놓고, 권한을 거부하면 설정 길을
// 보여 줬다가 돌아오면 다시 열고, 앱을 떠나면 카메라를 놓았다가 돌아오면 다시 엶
void main() {
  const en = S(AppLang.en);
  late FakeCameraPlatform camera;
  late CameraPlatform original;
  final preview = find.byKey(const ValueKey('camera-preview'));

  setUp(() {
    original = CameraPlatform.instance;
    camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });
  tearDown(() => CameraPlatform.instance = original);

  Future<List<String>> pumpScanner(WidgetTester tester) async {
    final codes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerView(
            onCode: (raw) {
              codes.add(raw);
              return raw.startsWith('intragram://');
            },
            hint: 'hint',
            noCamera: en.t('scanScreen.noCamera'),
            reticleSide: 200,
            reticleRadius: 12,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return codes;
  }

  Future<void> onAndroid(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  void lifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  // 프레임 구독 취소의 완료는 실제 이벤트 루프에서 와서(가짜 시간으로는 안 끝남) 잠깐 진짜로 돌림.
  // QR 풀기도 백그라운드 isolate라 같은 식으로 기다림
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  testWidgets('a code in the frames is handed over and the camera released', (
    tester,
  ) async {
    await onAndroid(() async {
      final codes = await pumpScanner(tester);
      expect(preview, findsOneWidget);
      expect(camera.streaming, isTrue);

      final code = deviceCode(
        host: '192.168.1.20',
        port: 7890,
        peerId: '0123456789abcdef0123456789abcdef',
      );
      camera.addFrame(qrFrame(code));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await settle(tester);

      expect(codes, [code]);
      expect(camera.streaming, isFalse);
      expect(camera.disposed, 1);
    });
  });

  testWidgets('a denied camera shows the settings path and comes back when '
      'the app returns', (tester) async {
    await onAndroid(() async {
      camera.denied = true;
      await pumpScanner(tester);
      expect(
        find.text(
          '${en.t('scan.cameraDenied')} ${en.t('scanScreen.noCamera')}',
        ),
        findsOneWidget,
      );
      expect(preview, findsNothing);

      // 권한 창이 닫히며 오는 복귀만으론 다시 안 물음 (Android가 연달아 묻지 않게)
      final attempts = camera.attempts;
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      await settle(tester);
      expect(camera.attempts, attempts);
      expect(preview, findsNothing);

      camera.denied = false; // 설정에 가서 켜고 돌아옴
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        lifecycle(tester, state);
      }
      await settle(tester);
      expect(preview, findsOneWidget);
      expect(camera.streaming, isTrue);
    });
  });

  testWidgets('leaving the app releases the camera and returning reopens it', (
    tester,
  ) async {
    await onAndroid(() async {
      await pumpScanner(tester);
      expect(camera.created, 1);

      lifecycle(tester, AppLifecycleState.inactive);
      await settle(tester);
      expect(camera.disposed, 1);
      expect(camera.streaming, isFalse);

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(camera.created, 2);
      expect(preview, findsOneWidget);
    });
  });

  testWidgets('closing the screen while the camera list loads opens nothing', (
    tester,
  ) async {
    await onAndroid(() async {
      camera.camerasGate = Completer<void>();
      await pumpScanner(tester);
      await tester.pumpWidget(const SizedBox());
      camera.camerasGate!.complete();
      await settle(tester);
      expect(camera.created, camera.disposed);
    });
  });

  testWidgets('a return while the camera list loads still opens one camera', (
    tester,
  ) async {
    await onAndroid(() async {
      camera.camerasGate = Completer<void>();
      await pumpScanner(tester);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      camera.camerasGate!.complete();
      await settle(tester);
      expect(camera.created - camera.disposed, 1);
      expect(preview, findsOneWidget);
    });
  });

  testWidgets('desktop has no camera path', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpScanner(tester);
      expect(find.text(en.t('scanScreen.noCamera')), findsOneWidget);
      expect(camera.created, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
