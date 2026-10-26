import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/audit/audit_bundle_exchange.dart';
import 'package:intragram/features/chat/widgets/add_people_sheet.dart';
import 'package:intragram/features/chat/widgets/attach_sheet.dart';
import 'package:intragram/features/chat/widgets/org_credential_dialog.dart';
import 'package:intragram/features/chat/widgets/room_member_list_dialog.dart';
import 'package:intragram/features/chat/widgets/sas_fingerprint_dialog.dart';
import 'package:intragram/features/home/home_actions.dart' show panicWipe;
import 'package:intragram/features/home/widgets/device_code_dialog.dart';
import 'package:intragram/features/home/widgets/manual_connect_dialog.dart';
import 'package:intragram/features/home/widgets/rename_identity_dialog.dart';
import 'package:intragram/features/home/widgets/wifi_info_dialog.dart';
import 'package:intragram/features/settings/pin_dialog.dart';
import 'package:intragram/network/org_auth.dart';

import '../support/test_identities.dart';
import '_harness.dart';

typedef _Open = void Function(BuildContext context, WidgetRef ref, Harness h);

void _dialog(BuildContext context, Widget dialog) =>
    showDialog<void>(context: context, builder: (_) => dialog);

final _dialogs = <String, _Open>{
  'connect by IP': (c, r, h) => _dialog(c, const ManualConnectDialog()),
  'rename': (c, r, h) =>
      _dialog(c, const RenameIdentityDialog(currentAlias: 'me-host-10')),
  'set PIN': (c, r, h) => PinDialog.show(c, alreadySet: false),
  'change PIN': (c, r, h) => PinDialog.show(c, alreadySet: true),
  'SAS': (c, r, h) => showSasFingerprintDialog(
    c,
    peerAlias: 'bob-owl-22',
    sas: '123456',
    localVerified: false,
    verified: false,
  ),
  'device code': (c, r, h) => showDeviceCodeDialog(
    c,
    host: '192.168.1.9',
    port: 7890,
    peerId: '0' * 32,
  ),
  'organization': (c, r, h) => showOrgCredentialDialog(
    c,
    book: OrgCredentialBook(),
    identity: testIdentity('a'),
    peerIds: ['1' * 32],
  ),
  'members': (c, r, h) => showRoomMemberListDialog(c, conv('c1')),
  'attach sheet': (c, r, h) => showAttachSheet(c),
  'add people sheet': (c, r, h) => showAddPeopleSheet(c, r, 'c1'),
  'wifi info': (c, r, h) => showWifiInfoDialog(c),
  'panic wipe': (c, r, h) => panicWipe(c, r),
  'witness exchange': (c, r, h) => _dialog(
    c,
    AuditBundleExchange(
      evidence: h.store.evidence,
      identity: testIdentity('a'),
    ),
  ),
};

// Android 17 플로팅 버블, iPhone Duo 커버 가로에 키보드, 작은 창의 큰 글씨, 큰 글씨에 키보드까지
// (버튼이 세로로 쌓여 버튼만으로 창을 넘던 경우)
const _windows = <(Size, double, double)>[
  (Size(320, 360), 160, 1),
  (Size(678, 466), 200, 1),
  (Size(320, 360), 0, 1.5),
  (Size(320, 360), 160, 2),
];

Future<Harness> _pump(
  WidgetTester tester,
  _Open open, {
  required Size size,
  double keyboard = 0,
  double textScale = 1,
  bool highContrast = false,
  List<DisplayFeature> features = const [],
}) async {
  // 앞 반복에서 연 대화상자가 남지 않게 앱을 새로 띄움
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store.upsertConversation(conv('c1'));
  await tester.pumpWidget(
    h.wrap(
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => open(context, ref, h),
          child: const Text('open'),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(textScale),
          highContrast: highContrast,
          displayFeatures: features,
        ),
        child: child!,
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

void main() {
  // 플랫폼별 대화상자 분기(iOS·macOS Cupertino, 데스크톱 모양·버튼 순서·420×560 최소 창)를 모두 검증함
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final MapEntry(key: name, value: open) in _dialogs.entries) {
      testWidgets('${platform.name} $name fits small windows and large text', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          for (final (size, keyboard, scale) in [
            ..._windows,
            if ([
              TargetPlatform.macOS,
              TargetPlatform.windows,
              TargetPlatform.linux,
            ].contains(platform))
              (const Size(420, 560), 0.0, 1.0),
          ]) {
            await _pump(
              tester,
              open,
              size: size,
              keyboard: keyboard,
              textScale: scale,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$size $keyboard $scale',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('dialogs stay on one side of a vertical hinge', (tester) async {
    for (final name in ['connect by IP', 'witness exchange', 'SAS']) {
      await _pump(
        tester,
        _dialogs[name]!,
        size: const Size(700, 840),
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(340, 0, 20, 840),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      expect(
        tester.getRect(find.byType(Dialog)).right,
        lessThanOrEqualTo(340),
        reason: name,
      );
      expect(tester.takeException(), isNull);
    }
  });

  // iOS 대화상자는 반투명 유리라 투명도 줄이기·대비 높이기(따로든 같이든)면 불투명 테마 대화상자로 바꿈
  testWidgets('iOS dialogs turn opaque under Reduce Transparency or contrast', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      for (final (reduced, contrast) in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ]) {
        OsPrivacy.reduceTransparency.value = reduced;
        await _pump(
          tester,
          _dialogs['connect by IP']!,
          size: const Size(320, 360),
          keyboard: 160,
          highContrast: contrast,
        );
        final opaque = reduced || contrast;
        expect(
          find.byType(CupertinoAlertDialog),
          opaque ? findsNothing : findsOne,
        );
        expect(find.byType(AlertDialog), opaque ? findsOne : findsNothing);
        expect(
          find.byType(CupertinoTextField),
          opaque ? findsNothing : findsWidgets,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      OsPrivacy.reduceTransparency.value = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
