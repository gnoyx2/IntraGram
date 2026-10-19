import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/features/home/widgets/home_sections.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/server_controller.dart';

// 사설 주소가 없는 망(공인 IPv4를 주는 캠퍼스·회사 Wi-Fi, CGNAT 핫스팟)은 "Wi-Fi 없음"과 다르게
// 안내함: 붙어 있는데도 못 쓰는 이유와 폰 핫스팟 우회
void main() {
  const en = S(AppLang.en);

  test('a public or CGNAT address is told apart from no network', () {
    expect(NetworkGuard.firstNonPrivate(['100.64.12.7']), '100.64.12.7');
    expect(NetworkGuard.firstNonPrivate(['203.0.113.5']), '203.0.113.5');
    expect(NetworkGuard.firstNonPrivate(['192.168.1.2', '10.0.0.3']), isNull);
    expect(NetworkGuard.firstNonPrivate(['169.254.3.4']), isNull);
    expect(NetworkGuard.firstNonPrivate(const []), isNull);
  });

  testWidgets('the banner for a public address names it and the hotspot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            server: ServerState(
              problem: ServerProblem.notPrivate,
              address: '100.64.12.7',
            ),
          ),
        ),
      ),
    );
    expect(find.text(en.t('server.notPrivateTitle')), findsOneWidget);
    expect(
      find.text(en.t('server.notPrivate', {'address': '100.64.12.7'})),
      findsOneWidget,
    );
  });

  testWidgets('no network keeps the join-Wi-Fi advice', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            server: ServerState(problem: ServerProblem.noNetwork),
          ),
        ),
      ),
    );
    expect(find.text(en.t('home.serverErrorHint')), findsOneWidget);
    expect(find.text(en.t('server.noNetwork')), findsOneWidget);
  });

  testWidgets('a failed start keeps the raw error behind Show details', (
    tester,
  ) async {
    const raw = 'Bad state: no free port from 7890';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            server: ServerState(problem: ServerProblem.failed, error: raw),
          ),
        ),
      ),
    );
    expect(find.text(en.t('server.failedTitle')), findsOneWidget);
    expect(find.text(en.t('home.serverErrorHint')), findsNothing);
    expect(find.textContaining(raw), findsNothing);

    await tester.tap(find.text(en.t('error.showDetail')));
    await tester.pump();
    expect(find.text(raw), findsOneWidget);
  });
}
