import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

SessionSummary _s(DateTime at, {int items = 10, int correct = 8}) => SessionSummary(
      endedAtMs: at.millisecondsSinceEpoch,
      durationSeconds: 300,
      itemsSeen: items,
      correct: correct,
      medianLatencyMs: 400,
    );

void main() {
  final today = DateTime(2026, 7, 21, 15, 0); // afternoon

  test('returns a contiguous run of the requested length ending today', () {
    final days = dailyActivity([], today: today, days: 14);
    expect(days.length, 14);
    expect(days.last.day, DateTime(2026, 7, 21));
    expect(days.first.day, DateTime(2026, 7, 8));
    // No sessions → all inactive.
    expect(days.every((d) => !d.active), isTrue);
  });

  test('buckets sessions into the correct calendar day', () {
    final sessions = [
      _s(DateTime(2026, 7, 21, 9)), // today, morning
      _s(DateTime(2026, 7, 21, 20)), // today, evening → same bucket
      _s(DateTime(2026, 7, 19, 12)), // two days ago
    ];
    final days = dailyActivity(sessions, today: today, days: 7);

    final todayCell = days.firstWhere((d) => d.day == DateTime(2026, 7, 21));
    expect(todayCell.sessions, 2);
    expect(todayCell.itemsSeen, 20);
    expect(todayCell.correct, 16);
    expect(todayCell.active, isTrue);

    final twoAgo = days.firstWhere((d) => d.day == DateTime(2026, 7, 19));
    expect(twoAgo.sessions, 1);

    final yesterday = days.firstWhere((d) => d.day == DateTime(2026, 7, 20));
    expect(yesterday.active, isFalse);
  });

  test('accuracy aggregates across a day', () {
    final sessions = [
      _s(DateTime(2026, 7, 21, 9), items: 10, correct: 10),
      _s(DateTime(2026, 7, 21, 10), items: 10, correct: 6),
    ];
    final days = dailyActivity(sessions, today: today, days: 3);
    final t = days.firstWhere((d) => d.day == DateTime(2026, 7, 21));
    expect(t.itemsSeen, 20);
    expect(t.correct, 16);
    expect((t.accuracy * 100).round(), 80);
  });

  test('sessions older than the window are excluded', () {
    final old = _s(DateTime(2026, 6, 1)); // way before the 14-day window
    final days = dailyActivity([old], today: today, days: 14);
    expect(days.every((d) => !d.active), isTrue);
  });

  test('wholeWeeks snaps to full Sunday→Saturday weeks', () {
    // 2026-07-21 is a Tuesday.
    final days = dailyActivity([], today: today, days: 84, wholeWeeks: true);
    // Count is a whole number of weeks.
    expect(days.length % 7, 0);
    // Starts on a Sunday (weekday 7) and ends on a Saturday (weekday 6).
    expect(days.first.day.weekday, DateTime.sunday);
    expect(days.last.day.weekday, DateTime.saturday);
    // The window ends on the Saturday of today's week (2026-07-25).
    expect(days.last.day, DateTime(2026, 7, 25));
  });
}
