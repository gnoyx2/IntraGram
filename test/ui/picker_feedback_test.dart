import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/registry/incoming_path_resolver.dart';
import 'package:intragram/widgets/picker_feedback.dart';

void main() {
  testWidgets('a missing file dialog says why instead of doing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => acceptWithPicker(
                context,
                () async => throw const PickerUnavailableException('no portal'),
              ),
              child: const Text('accept'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('accept'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('xdg-desktop-portal'), findsOneWidget);
  });
}
