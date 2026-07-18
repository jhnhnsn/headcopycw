/// Derives displayable progress from the SRS scheduler + curriculum.
/// Pure functions over [SrsScheduler] state so they can be unit-tested and
/// shared by the start-screen card and the full progress page.
library;

import 'curriculum.dart';
import 'srs.dart';

/// How far along the learner is with a single curriculum item.
enum ItemStatus {
  /// Cleared both the accuracy and ICR-latency gates — a reliable prerequisite.
  mastered,

  /// Introduced and being practised, but not yet mastered.
  learning,

  /// Not yet introduced.
  locked,
}

/// A curriculum item paired with the learner's current state on it.
class ItemProgress {
  final CurriculumItem item;
  final ItemStatus status;

  /// Rolling accuracy (0..1), or null if never seen.
  final double? accuracy;

  /// Median recognition latency in ms, or null if never seen.
  final int? medianLatencyMs;

  /// Total presentations.
  final int reps;

  const ItemProgress({
    required this.item,
    required this.status,
    required this.accuracy,
    required this.medianLatencyMs,
    required this.reps,
  });
}

/// Whole-curriculum roll-up for the summary card.
class ProgressSummary {
  final int total;
  final int unlocked; // introduced (learning + mastered)
  final int mastered;
  final int learning;

  const ProgressSummary({
    required this.total,
    required this.unlocked,
    required this.mastered,
    required this.learning,
  });

  int get locked => total - unlocked;

  /// Fraction of the curriculum unlocked (0..1).
  double get unlockedFraction => total == 0 ? 0 : unlocked / total;

  /// Fraction mastered (0..1).
  double get masteredFraction => total == 0 ? 0 : mastered / total;
}

/// Per-item progress across the whole curriculum, in curriculum order.
List<ItemProgress> itemProgressList(SrsScheduler scheduler) {
  final cfg = scheduler.config;
  return [
    for (final item in kCurriculum)
      _progressFor(item, scheduler.states[item.id], cfg),
  ];
}

ItemProgress _progressFor(CurriculumItem item, ItemState? st, SrsConfig cfg) {
  if (st == null || !st.introduced) {
    return ItemProgress(
      item: item,
      status: ItemStatus.locked,
      accuracy: null,
      medianLatencyMs: null,
      reps: 0,
    );
  }
  final mastered = st.isMastered(cfg);
  return ItemProgress(
    item: item,
    status: mastered ? ItemStatus.mastered : ItemStatus.learning,
    accuracy: st.accuracy,
    // medianLatencyMs returns a huge sentinel when no latencies exist; treat
    // that as unknown.
    medianLatencyMs: st.recentLatencyMs.isEmpty ? null : st.medianLatencyMs,
    reps: st.reps,
  );
}

/// Roll-up counts for the summary card.
ProgressSummary summarize(SrsScheduler scheduler) {
  var unlocked = 0, mastered = 0, learning = 0;
  final cfg = scheduler.config;
  for (final item in kCurriculum) {
    final st = scheduler.states[item.id];
    if (st == null || !st.introduced) continue;
    unlocked++;
    if (st.isMastered(cfg)) {
      mastered++;
    } else {
      learning++;
    }
  }
  return ProgressSummary(
    total: kCurriculum.length,
    unlocked: unlocked,
    mastered: mastered,
    learning: learning,
  );
}
