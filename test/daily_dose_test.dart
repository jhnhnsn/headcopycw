import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

SessionSummary _s(DateTime endedAt, int durationSeconds) => SessionSummary(
      endedAtMs: endedAt.millisecondsSinceEpoch,
      durationSeconds: durationSeconds,
      itemsSeen: 10,
      correct: 9,
      medianLatencyMs: 400,
    );

void main() {
  final today = DateTime(2026, 7, 23, 14, 0);

  test('sums only sessions ended on today\'s calendar day', () {
    final sessions = [
      _s(DateTime(2026, 7, 23, 9), 300), // today
      _s(DateTime(2026, 7, 23, 20), 300), // today (evening)
      _s(DateTime(2026, 7, 22, 23, 59), 300), // yesterday
      _s(DateTime(2026, 7, 24, 0, 1), 300), // tomorrow
    ];
    expect(secondsPracticedToday(sessions, today), 600);
  });

  test('zero when nothing today', () {
    expect(secondsPracticedToday([_s(DateTime(2026, 7, 20), 900)], today), 0);
    expect(secondsPracticedToday(const [], today), 0);
  });

  test('daily-dose target is the ~30 min research consensus', () {
    expect(kDailyDoseTargetSeconds, 30 * 60);
  });

  test('crosses the target after enough same-day practice', () {
    final sessions = [
      _s(DateTime(2026, 7, 23, 8), 15 * 60),
      _s(DateTime(2026, 7, 23, 12), 16 * 60),
    ];
    expect(secondsPracticedToday(sessions, today),
        greaterThan(kDailyDoseTargetSeconds));
  });
}
