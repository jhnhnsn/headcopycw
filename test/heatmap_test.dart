// Renders the ActivityHeatmap calendar with known data and asserts it lays out
// without overflow. (No AudioPlayer here, so no plugin hang.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_page.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  testWidgets('calendar grid renders 12 weeks without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final today = DateTime(2026, 7, 21);
    // A couple of active days scattered in the window.
    final sessions = [
      SessionSummary(
        endedAtMs: DateTime(2026, 7, 20, 10).millisecondsSinceEpoch,
        durationSeconds: 300, itemsSeen: 20, correct: 18, medianLatencyMs: 400,
      ),
      SessionSummary(
        endedAtMs: DateTime(2026, 6, 15, 9).millisecondsSinceEpoch,
        durationSeconds: 300, itemsSeen: 10, correct: 7, medianLatencyMs: 500,
      ),
    ];
    final days = dailyActivity(sessions, today: today, days: 84, wholeWeeks: true);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ActivityHeatmap(days: days),
        ),
      ),
    ));
    await tester.pump();

    // Built cleanly, no layout overflow exception.
    expect(tester.takeException(), isNull);
    // Weekday labels present.
    expect(find.text('M'), findsWidgets);
    expect(find.text('W'), findsWidgets);
  });

  testWidgets('empty history renders nothing (no crash)',
      (WidgetTester tester) async {
    final days = dailyActivity([], today: DateTime(2026, 7, 21), days: 84);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ActivityHeatmap(days: days)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
