/// Derives displayable progress from the SRS scheduler + curriculum.
/// Pure functions over [SrsScheduler] state so they can be unit-tested and
/// shared by the start-screen card and the full progress page.
library;

import 'curriculum.dart';
import 'progress_store.dart';
import 'srs.dart';

/// One calendar day's practice activity, for the activity heatmap.
class DayActivity {
  /// Local date at midnight (year/month/day only).
  final DateTime day;
  final int sessions;
  final int itemsSeen;
  final int correct;

  const DayActivity({
    required this.day,
    required this.sessions,
    required this.itemsSeen,
    required this.correct,
  });

  double get accuracy => itemsSeen == 0 ? 0 : correct / itemsSeen;
  bool get active => sessions > 0;
}

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// Weekday index with Sunday = 0 .. Saturday = 6 (DateTime: Mon=1..Sun=7).
int _weekdaySun0(DateTime d) => d.weekday % 7;

/// Builds a contiguous run of daily activity ending on [today], oldest → newest,
/// each filled with that day's aggregated session activity (empty days included
/// so the heatmap shows gaps/streaks). Sessions are keyed by their
/// [SessionSummary.endedAtMs] wall-clock timestamp.
///
/// When [wholeWeeks] is true, the window is snapped to full Sunday→Saturday
/// weeks: it ends on the Saturday of [today]'s week and begins on a Sunday so
/// the calendar renders as a clean rectangle (no ragged first/last column).
List<DayActivity> dailyActivity(
  List<SessionSummary> sessions, {
  required DateTime today,
  int days = 14,
  bool wholeWeeks = false,
}) {
  // Aggregate sessions into per-day buckets.
  final buckets = <DateTime, List<SessionSummary>>{};
  for (final s in sessions) {
    final d = _midnight(DateTime.fromMillisecondsSinceEpoch(s.endedAtMs));
    (buckets[d] ??= []).add(s);
  }

  // Use calendar arithmetic (DateTime(y, m, d + n)), NOT Duration(days: n):
  // a Duration is exactly 24h, so across a DST change it drifts onto the wrong
  // calendar day and mis-aligns the weekday grid.
  DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  DateTime end = _midnight(today);
  var count = days;
  if (wholeWeeks) {
    // Extend end to the Saturday of the current week (Sat is 6 in Sun=0 terms).
    end = addDays(end, 6 - _weekdaySun0(end));
    // Round the span up to a whole number of weeks.
    final weeks = (days / 7).ceil();
    count = weeks * 7;
  }

  final out = <DayActivity>[];
  for (var i = count - 1; i >= 0; i--) {
    final day = addDays(end, -i);
    final b = buckets[day] ?? const [];
    var items = 0, correct = 0;
    for (final s in b) {
      items += s.itemsSeen;
      correct += s.correct;
    }
    out.add(DayActivity(
      day: day,
      sessions: b.length,
      itemsSeen: items,
      correct: correct,
    ));
  }
  return out;
}

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

/// Human-readable name for a curriculum tier. Kept deliberately coarse — a
/// milestone, never the specific next item — so it motivates without priming
/// the learner on what sound is coming.
String tierName(int tier) {
  switch (tier) {
    case 1:
      return 'the contact basics';
    case 2:
      return 'exchanges & numbers';
    case 3:
      return 'common words';
    case 4:
      return 'callsigns';
    default:
      return 'more material';
  }
}

/// A non-spoiling progress nudge: describes the tier the learner is working
/// through and how close they are to finishing it — NEVER the next specific
/// item or its immediate identity. Returns null when nothing meaningful applies
/// (nothing started, or the whole curriculum is done).
String? milestoneNudge(SrsScheduler scheduler, List<CurriculumItem> curriculum) {
  // Find the first not-yet-introduced item; the tier it belongs to is the one
  // currently being worked into.
  CurriculumItem? nextLocked;
  for (final it in curriculum) {
    final st = scheduler.states[it.id];
    if (st == null || !st.introduced) {
      nextLocked = it;
      break;
    }
  }
  if (nextLocked == null) return null; // curriculum complete

  final tier = nextLocked.tier;
  final tierItems = curriculum.where((it) => it.tier == tier).toList();
  if (tierItems.isEmpty) return null;
  final introduced = tierItems
      .where((it) => scheduler.states[it.id]?.introduced ?? false)
      .length;

  // Nothing in this tier started yet → don't nudge (would hint the next item).
  if (introduced == 0) return null;

  final remaining = tierItems.length - introduced;
  final name = tierName(tier);
  if (remaining <= 2) {
    return 'Almost through $name';
  }
  final pct = (introduced / tierItems.length * 100).round();
  return '$pct% through $name';
}

/// Per-item progress across the whole curriculum, in curriculum order.
/// [curriculum] defaults to the fixed [kCurriculum]; pass a composed curriculum
/// (e.g. including the user's callsign) to reflect it in the item map.
List<ItemProgress> itemProgressList(SrsScheduler scheduler,
    {List<CurriculumItem>? curriculum}) {
  final cfg = scheduler.config;
  return [
    for (final item in (curriculum ?? kCurriculum))
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

/// Roll-up counts for the summary card. [curriculum] defaults to the fixed
/// [kCurriculum]; pass a composed curriculum to include e.g. the callsign item.
ProgressSummary summarize(SrsScheduler scheduler,
    {List<CurriculumItem>? curriculum}) {
  final items = curriculum ?? kCurriculum;
  var unlocked = 0, mastered = 0, learning = 0;
  final cfg = scheduler.config;
  for (final item in items) {
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
    total: items.length,
    unlocked: unlocked,
    mastered: mastered,
    learning: learning,
  );
}
