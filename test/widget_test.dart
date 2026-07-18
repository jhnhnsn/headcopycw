// Smoke test: the trainer page boots and exposes the mode navigation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:head_copy_cw_trainer/cw_trainer_page.dart';

void main() {
  testWidgets('CwTrainerPage boots into Copy mode',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CwTrainerPage()));
    await tester.pump();

    // Copy is the default full-screen mode (title in the app bar); the legacy
    // drills now live behind the overflow menu rather than a bottom nav.
    expect(find.text('Copy'), findsWidgets);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });
}
