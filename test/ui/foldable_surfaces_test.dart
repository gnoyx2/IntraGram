import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/features/chat/audit_proof_sheet.dart';
import 'package:intragram/features/portal/portal_sheet.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/widgets/scanner_frame.dart';

import '../support/test_identities.dart';
import '_harness.dart';

const _tabletop = DisplayFeature(
  bounds: Rect.fromLTWH(0, 400, 700, 20),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);
const _hinge = DisplayFeature(
  bounds: Rect.fromLTWH(340, 0, 20, 840),
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.unknown,
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

TransitionBuilder _media({
  List<DisplayFeature> features = const [],
  double keyboard = 0,
}) =>
    (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        displayFeatures: features,
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: child!,
    );

Widget _openPortal() => Builder(
  builder: (context) => Scaffold(
    body: TextButton(
      onPressed: () => PortalSheet.show(context),
      child: const Text('open'),
    ),
  ),
);

void main() {
  testWidgets('tabletop portal keeps QR above crease and controls below', (
    tester,
  ) async {
    _size(tester, const Size(700, 840));
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        _openPortal(),
        overrides: [serverControllerProvider.overrideWith(_RunningServer.new)],
        builder: _media(features: [_tabletop]),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      tester.getRect(find.byType(QrImageView)).bottom,
      lessThanOrEqualTo(400),
    );
    expect(
      tester.getRect(find.text('Guest portal')).top,
      greaterThanOrEqualTo(420),
    );
    await tester.scrollUntilVisible(
      find.text('Local web server'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal modal and audit dialog avoid a vertical hinge', (
    tester,
  ) async {
    _size(tester, const Size(700, 840));
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(_openPortal(), builder: _media(features: [_hinge])),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(PortalSheet)).right,
      lessThanOrEqualTo(340),
    );
    final context = tester.element(find.byType(PortalSheet));
    Navigator.pop(context);
    await tester.pumpAndSettle();
    showAuditProofSheet(
      tester.element(find.text('open')),
      h.store.evidence,
      testIdentity('a'),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Dialog)).right, lessThanOrEqualTo(340));
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating bubble PIN gate scrolls above the keyboard', (
    tester,
  ) async {
    _size(tester, const Size(320, 360));
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(const PinGateScreen(), builder: _media(keyboard: 140)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.textContaining('Start fresh'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getRect(find.textContaining('Start fresh')).bottom,
      lessThanOrEqualTo(220),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating bubble audit stays constrained and scrollable', (
    tester,
  ) async {
    _size(tester, const Size(320, 360));
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        AuditProofSheet(
          evidence: h.store.evidence,
          identity: testIdentity('a'),
        ),
        builder: _media(keyboard: 140),
      ),
    );
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byType(ListView));
    expect(dialog.right, lessThanOrEqualTo(320));
    expect(dialog.bottom, lessThanOrEqualTo(220));
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabletop scanner reticle and guidance avoid crease', (
    tester,
  ) async {
    _size(tester, const Size(700, 840));
    // 실제 폰처럼 상태 표시줄을 둠 (본문 안에선 위 여백이 지워져 접힘선 기준점이 어긋나기 쉬움)
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final h = Harness();
    addTearDown(h.dispose);
    final camera = CameraController(
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 0,
      ),
      ResolutionPreset.medium,
      enableAudio: false,
    );
    addTearDown(camera.dispose);
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          appBar: AppBar(title: const Text('Scan')),
          body: ScannerFrame(
            camera: camera,
            previewSize: const Size(640, 480),
            hint: 'Scanner guidance',
            reticleSide: 280,
            reticleRadius: 20,
          ),
        ),
        builder: _media(features: [_tabletop]),
      ),
    );
    final reticle = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border != null,
    );
    expect(tester.getRect(reticle).bottom, lessThanOrEqualTo(400));
    expect(
      tester.getRect(find.text('Scanner guidance')).top,
      greaterThanOrEqualTo(420),
    );
    expect(tester.takeException(), isNull);
  });
}

class _RunningServer extends ServerController {
  @override
  ServerState build() => const ServerState(
    running: true,
    host: '192.168.1.9',
    port: 7890,
    portalEnabled: true,
    portalToken: 'test-token',
  );
}
