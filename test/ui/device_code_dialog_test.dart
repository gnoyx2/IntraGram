import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/features/home/widgets/device_code_dialog.dart';

// 기기 코드는 사설 주소일 때만 QR로, 아니면 이유 문구로 보임
void main() {
  const peerId = '0123456789abcdef0123456789abcdef';

  Future<void> open(WidgetTester tester, {String? host, int? port}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeviceCodeDialog(
              context,
              host: host,
              port: port,
              peerId: peerId,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a private address shows the device code', (tester) async {
    await open(tester, host: '192.168.0.7', port: 7890);
    expect(find.byType(QrImageView), findsOne);
    expect(find.textContaining('only completes with this device'), findsOne);
  });

  testWidgets('no private address explains why there is no code', (
    tester,
  ) async {
    await open(tester, host: '100.64.0.9', port: 7890);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('private Wi-Fi address'), findsOne);
  });
}
