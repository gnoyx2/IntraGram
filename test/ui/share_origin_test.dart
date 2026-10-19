import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/widgets/share_origin.dart';

void main() {
  testWidgets('the share popover anchors on the pressed button', (
    tester,
  ) async {
    Rect? origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topRight,
          child: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => origin = shareOrigin(context),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    expect(origin, tester.getRect(find.byType(IconButton)));
  });
}
