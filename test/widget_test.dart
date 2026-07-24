// Smoke test: the app boots into the (single) Copy screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:head_copy_cw_trainer/cw_trainer_page.dart';

void main() {
  testWidgets('CwTrainerPage boots into Copy', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CwTrainerPage()));
    await tester.pump();

    // Copy is the whole app now: the app-bar title names the app, and there is
    // no drills overflow menu or bottom navigation.
    expect(find.text('Head Copy CW Trainer'), findsWidgets);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
