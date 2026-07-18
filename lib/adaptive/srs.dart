/// Spaced-repetition scheduler for the adaptive "Copy" mode.
///
/// Unlike a flashcard SRS, this schedules *sound-chunks* (characters, words,
/// short phrases) and is driven by two signals grounded in the research:
///   1. accuracy  — did the learner copy it correctly?
///   2. latency   — how fast did they recognise it? (instant character/word
///      recognition, ICR/IWR). A slow-but-correct answer still counts as a
///      recognition failure for the purposes of *unlocking new material*,
///      because it means the learner is still consciously decoding.
///
/// Scheduling is measured in **session reps**, not wall-clock time. Practice is
/// bursty (a few minutes at a time, days apart); rep-based intervals avoid the
/// "everything is due after a week away" collapse that wall-clock SRS suffers.
library;

import 'dart:math';

/// Accuracy an item's rolling average must reach to be considered "mastered".
const double kAccuracyGate = 0.90;

/// Response-time ceiling (ms, audio-end → submit) for an item to count as
/// instantly recognised. ~550ms follows the CWops/MorseCode.World ICR
/// guideline (sub-600ms) and the ~500ms figure used by ICR trainers.
const int kIcrLatencyMs = 550;

/// How many of the most recent grades feed the rolling accuracy/latency stats.
const int kRollingWindow = 8;

/// Leitner box intervals, in session reps, indexed by box number.
/// A correct answer promotes to the next box (longer interval); an incorrect
/// answer demotes toward box 0 (seen again almost immediately).
const List<int> kBoxIntervals = [1, 2, 4, 8, 16, 32];

/// Probability of introducing a brand-new curriculum item on a given rep,
/// *when the introduce-new gates are satisfied*. Tunable via [SrsConfig].
const double kDefaultIntroduceProbability = 0.25;

/// Weighting knobs for [SrsScheduler.pickNext] and gating.
class SrsConfig {
  final double accuracyGate;
  final int icrLatencyMs;
  final double introduceProbability;

  const SrsConfig({
    this.accuracyGate = kAccuracyGate,
    this.icrLatencyMs = kIcrLatencyMs,
    this.introduceProbability = kDefaultIntroduceProbability,
  });
}

/// Per-item spaced-repetition state. Pure data; JSON-serialisable so
/// [progress_store] can persist it.
class ItemState {
  /// Stable id of the curriculum item this state tracks.
  final String id;

  /// Leitner box (0..kBoxIntervals.length-1). Higher = better retained.
  int box;

  /// Total times this item has been presented.
  int reps;

  /// The session-rep index at which this item becomes due again.
  int dueAtRep;

  /// Most recent grades (true = correct), newest last, capped at kRollingWindow.
  final List<bool> recentCorrect;

  /// Most recent latencies in ms (audio-end → submit), newest last, capped.
  final List<int> recentLatencyMs;

  ItemState({
    required this.id,
    this.box = 0,
    this.reps = 0,
    this.dueAtRep = 0,
    List<bool>? recentCorrect,
    List<int>? recentLatencyMs,
  })  : recentCorrect = recentCorrect ?? <bool>[],
        recentLatencyMs = recentLatencyMs ?? <int>[];

  /// True once the item has been introduced (presented at least once).
  bool get introduced => reps > 0;

  /// Rolling accuracy over the recent window (1.0 if never seen).
  double get accuracy {
    if (recentCorrect.isEmpty) return 1.0;
    final hits = recentCorrect.where((c) => c).length;
    return hits / recentCorrect.length;
  }

  /// Median of recent latencies in ms (returns [maxInt]-ish sentinel if none),
  /// used as a robust central tendency less swayed by a single slow answer.
  int get medianLatencyMs {
    if (recentLatencyMs.isEmpty) return 1 << 30;
    final sorted = [...recentLatencyMs]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  /// An item is "mastered" — and therefore able to satisfy a prerequisite —
  /// only when it clears BOTH the accuracy and the latency (ICR) gates.
  bool isMastered(SrsConfig config) {
    if (recentCorrect.length < 3) return false; // need some evidence
    return accuracy >= config.accuracyGate &&
        medianLatencyMs <= config.icrLatencyMs;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'box': box,
        'reps': reps,
        'dueAtRep': dueAtRep,
        'recentCorrect': recentCorrect,
        'recentLatencyMs': recentLatencyMs,
      };

  factory ItemState.fromJson(Map<String, dynamic> j) => ItemState(
        id: j['id'] as String,
        box: (j['box'] as num?)?.toInt() ?? 0,
        reps: (j['reps'] as num?)?.toInt() ?? 0,
        dueAtRep: (j['dueAtRep'] as num?)?.toInt() ?? 0,
        recentCorrect:
            (j['recentCorrect'] as List?)?.map((e) => e as bool).toList() ??
                <bool>[],
        recentLatencyMs: (j['recentLatencyMs'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            <int>[],
      );
}

/// Result of grading one presentation.
class GradeResult {
  final bool correct;
  final int latencyMs;
  final bool countedAsRecognised;
  GradeResult({
    required this.correct,
    required this.latencyMs,
    required this.countedAsRecognised,
  });
}

/// The scheduler. Holds a map of item id → [ItemState] plus a session-rep
/// counter. It is deliberately free of any Flutter/IO dependency so it can be
/// unit-tested in isolation.
class SrsScheduler {
  final SrsConfig config;
  final Map<String, ItemState> states;

  /// Monotonic count of presentations this run; drives due scheduling.
  int repCounter;

  final Random _rng;

  SrsScheduler({
    this.config = const SrsConfig(),
    Map<String, ItemState>? states,
    this.repCounter = 0,
    Random? rng,
  })  : states = states ?? <String, ItemState>{},
        _rng = rng ?? Random();

  ItemState _stateFor(String id) =>
      states.putIfAbsent(id, () => ItemState(id: id));

  /// Grade a presentation of [id]. [correct] is the accuracy verdict; a correct
  /// answer that beats the ICR latency gate is [countedAsRecognised] and
  /// promotes the Leitner box. Correct-but-slow holds the box (consolidating);
  /// incorrect demotes toward box 0.
  GradeResult grade({
    required String id,
    required bool correct,
    required int latencyMs,
  }) {
    final s = _stateFor(id);
    s.reps++;

    _pushCapped(s.recentCorrect, correct);
    _pushCapped(s.recentLatencyMs, latencyMs);

    final recognised = correct && latencyMs <= config.icrLatencyMs;

    if (!correct) {
      // Demote sharply: back toward the start so it is re-seen almost at once.
      s.box = max(0, s.box - 2);
    } else if (recognised) {
      // Promote: earned a longer interval.
      s.box = min(kBoxIntervals.length - 1, s.box + 1);
    } else {
      // Correct but slow: hold box, keep consolidating at the same interval.
    }

    s.dueAtRep = repCounter + kBoxIntervals[s.box];
    return GradeResult(
      correct: correct,
      latencyMs: latencyMs,
      countedAsRecognised: recognised,
    );
  }

  /// Whether the next locked item may be introduced now: overall recent
  /// performance must be healthy (in/above the desirable-difficulty band) so we
  /// don't pile new material onto a struggling learner.
  bool canIntroduceNew() {
    final active = states.values.where((s) => s.introduced).toList();
    if (active.isEmpty) return true; // nothing yet — always seed the first item
    // Aggregate accuracy across all recently-seen items.
    var hits = 0, total = 0;
    for (final s in active) {
      hits += s.recentCorrect.where((c) => c).length;
      total += s.recentCorrect.length;
    }
    if (total == 0) return true;
    return hits / total >= config.accuracyGate;
  }

  /// True if every prerequisite id is mastered (both gates). Missing/never-seen
  /// prerequisites count as unmastered.
  bool prereqsMet(Iterable<String> prereqIds) {
    for (final pid in prereqIds) {
      final s = states[pid];
      if (s == null || !s.isMastered(config)) return false;
    }
    return true;
  }

  /// Pick the id of the next item to present.
  ///
  /// [introducedIds] are the ids already unlocked (have state or should be
  /// scheduled). [nextLockedItem] is the id of the next curriculum item to
  /// introduce along with its prerequisite ids, or null if the curriculum is
  /// exhausted. Selection:
  ///   1. If gates allow and a dice roll fires, introduce the next locked item.
  ///   2. Otherwise pick the "most due" introduced item, weighted toward items
  ///      that are overdue and low-accuracy.
  ///
  /// Increments [repCounter]. Returns null only if there is nothing to present.
  String? pickNext({
    required List<String> introducedIds,
    ({String id, List<String> prereqs})? nextLockedItem,
  }) {
    repCounter++;

    // 1. Consider introducing new material.
    final canIntro = nextLockedItem != null &&
        canIntroduceNew() &&
        prereqsMet(nextLockedItem.prereqs);
    if (canIntro) {
      final forced = introducedIds.isEmpty; // always seed the very first item
      if (forced || _rng.nextDouble() < config.introduceProbability) {
        return nextLockedItem.id;
      }
    }

    if (introducedIds.isEmpty) {
      // Gates blocked and nothing introduced yet: fall back to seeding if we can.
      return nextLockedItem?.id;
    }

    // 2. Weighted pick among introduced items, favouring due + weak items.
    String? best;
    double bestWeight = -1;
    for (final id in introducedIds) {
      final s = states[id];
      final overdue = s == null ? 0 : (repCounter - s.dueAtRep);
      // Only items at/after their due rep are eligible; if none are due yet,
      // still allow the most-overdue (least-negative) so we never stall.
      final dueBonus = overdue >= 0 ? 1.0 + overdue : 1.0 / (1 - overdue);
      final weakness = s == null ? 1.0 : (1.0 - s.accuracy);
      // Small jitter breaks ties without an external clock.
      final weight = dueBonus * (0.5 + weakness) * (0.85 + 0.3 * _rng.nextDouble());
      if (weight > bestWeight) {
        bestWeight = weight;
        best = id;
      }
    }
    return best;
  }

  void _pushCapped<T>(List<T> list, T value) {
    list.add(value);
    while (list.length > kRollingWindow) {
      list.removeAt(0);
    }
  }
}
