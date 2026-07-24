// Smoke test: the app boots into the (single) Copy screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:head_copy_cw_trainer/cw_trainer_page.dart';
import 'package:head_copy_cw_trainer/headcopy_wordmark.dart';

void main() {
  testWidgets('CwTrainerPage boots into Copy', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CwTrainerPage()));
    await tester.pump();

    // Copy is the whole app now: the app-bar shows the HeadCopy wordmark, and
    // there is no drills overflow menu or bottom navigation.
    expect(find.byType(HeadCopyWordmark), findsWidgets);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
