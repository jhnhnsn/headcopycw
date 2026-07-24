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

import 'confusables.dart';

/// Accuracy an item's rolling average must reach to be considered "mastered"
/// (used to satisfy a word/phrase's character prerequisites). Kept strict —
/// you want the letters of a word genuinely solid before hearing the word.
const double kAccuracyGate = 0.90;

/// Accuracy gate for *promoting* the learner to a new item — deliberately lower
/// than mastery. Research (the "85% rule" for perceptual learning; modern SRS
/// retention optima ~80–90%) indicates the classic Koch 90% promotion bar is
/// conservative and slows progression without benefit. This is the "add the
/// next item" knob, separate from the "this word's letters are solid" knob.
const double kPromotionGate = 0.85;

/// Response-time ceiling (ms, audio-end → submit) for an item to count as
/// instantly recognised. ~550ms follows the CWops/MorseCode.World ICR
/// guideline (sub-600ms) and the ~500ms figure used by ICR trainers.
const int kIcrLatencyMs = 550;

/// How many of the most recent grades feed the rolling accuracy/latency stats.
const int kRollingWindow = 8;

/// Bounds for the adaptive effective (Farnsworth) speed ramp. Effective speed
/// never exceeds the fixed character speed (see kFixedActualWpm).
const int kMinEffectiveWpm = 8;
const int kMaxEffectiveWpm = 20;

/// Decides the next adaptive effective-WPM from the current value and a
/// completed session's aggregate performance. Pure so it's easy to test.
///
/// Ramps UP when a session was strong (high accuracy AND fast median
/// recognition, with enough items to trust it) — the same signals that gate
/// item unlocks, applied to speed. Eases DOWN when accuracy fell well below the
/// gate, so a speed bump that hurt gets undone. Otherwise holds.
int adaptEffectiveWpm({
  required int current,
  required int itemsSeen,
  required double accuracy,
  required int medianLatencyMs,
  double accuracyGate = kAccuracyGate,
  int icrLatencyMs = kIcrLatencyMs,
}) {
  // Too little evidence to move either way.
  if (itemsSeen < 8) return current;

  final strong = accuracy >= accuracyGate && medianLatencyMs <= icrLatencyMs;
  final struggling = accuracy < accuracyGate - 0.15; // ~<75%

  if (strong) {
    return (current + 1).clamp(kMinEffectiveWpm, kMaxEffectiveWpm);
  }
  if (struggling) {
    return (current - 1).clamp(kMinEffectiveWpm, kMaxEffectiveWpm);
  }
  return current;
}

// ---- Adaptive "copy-behind" buffer ----
//
// Research-grounded (CWops CW Academy sequencing; expertise-reversal; Toppino
// 2018 grow-with-mastery; Pierpont's 1–2-words-behind cap; Baddeley loop):
//   * Copy-behind is an ADVANCED skill — keep the buffer at 0 until the learner
//     has demonstrated instant recognition on a base of items (the gate).
//   * Then INTRODUCE and GROW a silent delay toward a ceiling, but only while
//     accuracy stays high WITH the delay active (a retention-specific signal,
//     kept separate from the speed adapter so difficulty isn't double-driven).
//   * Ease back if accuracy suffers; hold at the hardest reliably-successful
//     delay rather than growing forever.

/// Number of mastered items before the copy-behind buffer is introduced (the
/// ICR → copy-behind gate).
const int kBufferGateMasteredItems = 15;

/// Buffer bounds (ms). Starts here once the gate opens; grows toward the max
/// (~2s ≈ one phonological-loop lifetime / "a word or two behind").
const int kBufferStartMs = 400;
const int kBufferMaxMs = 2000;
const int kBufferStepMs = 150;

/// Decides the next copy-behind buffer (ms) from the current value, the mastery
/// count, and the accuracy observed *with the buffer active this session*.
/// Pure/testable.
///
/// - Below the mastery gate → 0 (pure ICR phase).
/// - At/after the gate, buffer 0 → introduce [kBufferStartMs].
/// - Buffer active: grow while accuracy stays high; ease back if it drops;
///   otherwise hold. [bufferedItems] guards against moving on thin evidence.
int adaptBufferMs({
  required int current,
  required int masteredCount,
  required int bufferedItems,
  required double bufferedAccuracy,
  double accuracyGate = kAccuracyGate,
}) {
  // Gate: no copy-behind until instant recognition is established.
  if (masteredCount < kBufferGateMasteredItems) return 0;

  // Just crossed the gate with no buffer yet → introduce a small one.
  if (current <= 0) return kBufferStartMs;

  // Not enough buffered evidence this session → hold.
  if (bufferedItems < 8) return current;

  final strong = bufferedAccuracy >= accuracyGate;
  final struggling = bufferedAccuracy < accuracyGate - 0.15; // ~<75%

  if (strong) {
    return (current + kBufferStepMs).clamp(kBufferStartMs, kBufferMaxMs);
  }
  if (struggling) {
    // Ease back toward (but not below) the introductory buffer.
    return (current - kBufferStepMs).clamp(kBufferStartMs, kBufferMaxMs);
  }
  return current;
}

/// The "too slow to answer" bar's target for one item, in ms — adaptive to the
/// learner's own recent pace rather than a fixed constant, so it tightens as
/// they speed up. Pure/testable.
///
/// The per-character allowance is `median(history) × margin`, clamped to at
/// least [floorMs] (so a typed bar still nudges toward the ICR target). With no
/// history yet, [fallbackPerCharMs] is used so early sessions still show a
/// sensible bar. Total = perChar × charCount, bounded to a reasonable window.
int elapsedTargetMs({
  required List<int> history,
  required int charCount,
  double margin = 1.7,
  int floorMs = 0,
  int fallbackPerCharMs = 550,
}) {
  final chars = charCount.clamp(1, 30);
  int perChar;
  if (history.isEmpty) {
    perChar = fallbackPerCharMs;
  } else {
    final sorted = [...history]..sort();
    final med = sorted[sorted.length ~/ 2];
    // History is a per-item total; approximate its per-char pace. (Most items
    // are short, so this stays close to the raw median for single chars.)
    perChar = (med * margin).round();
  }
  if (perChar < floorMs) perChar = floorMs;
  // Scale gently with length rather than strictly linearly (long phrases get
  // proportionally less time per char once you're in a rhythm).
  final total = (perChar * (0.6 + 0.4 * chars)).round();
  return total.clamp(1200, 15000);
}

/// Leitner box intervals, in session reps, indexed by box number.
/// A correct answer promotes to the next box (longer interval); an incorrect
/// answer demotes toward box 0 (seen again almost immediately).
const List<int> kBoxIntervals = [1, 2, 4, 8, 16, 32];

/// Probability of introducing a brand-new curriculum item on a given rep,
/// *when the introduce-new gates are satisfied*. Tunable via [SrsConfig].
const double kDefaultIntroduceProbability = 0.25;

/// Weighting knobs for [SrsScheduler.pickNext] and gating.
class SrsConfig {
  /// Mastery gate (satisfying a word's character prerequisites).
  final double accuracyGate;

  /// Promotion gate (adding the next new item) — lower than mastery.
  final double promotionGate;
  final int icrLatencyMs;
  final double introduceProbability;

  const SrsConfig({
    this.accuracyGate = kAccuracyGate,
    this.promotionGate = kPromotionGate,
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

  /// Per-character rolling correctness observed *inside any item* (from typed
  /// per-character diffs). Char → recent bools (newest last, capped). This is
  /// how a character fumbled inside a word (e.g. the S in "SOS") still marks
  /// that character weak and drives confusable practice — separate from the
  /// whole-item [states].
  final Map<String, List<bool>> charRecent;

  /// Monotonic count of presentations this run; drives due scheduling.
  int repCounter;

  final Random _rng;

  SrsScheduler({
    this.config = const SrsConfig(),
    Map<String, ItemState>? states,
    Map<String, List<bool>>? charRecent,
    this.repCounter = 0,
    Random? rng,
  })  : states = states ?? <String, ItemState>{},
        charRecent = charRecent ?? <String, List<bool>>{},
        _rng = rng ?? Random();

  ItemState _stateFor(String id) =>
      states.putIfAbsent(id, () => ItemState(id: id));

  /// Rolling accuracy for a single character across all items (1.0 if unseen).
  double charAccuracy(String ch) {
    final r = charRecent[ch];
    if (r == null || r.isEmpty) return 1.0;
    return r.where((c) => c).length / r.length;
  }

  /// Records per-character outcomes from a typed answer vs. the target, so a
  /// character fumbled inside a word feeds weak-char reinforcement and
  /// confusable practice. Position-aligned (the common case); when the typed
  /// answer is a different length, only the overlapping positions are scored.
  /// Both strings should already be normalised (uppercase, single-spaced).
  void recordCharOutcomes(String target, String typed) {
    final t = target.replaceAll(' ', '');
    final u = typed.replaceAll(' ', '');
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (!kConfusableScorable.contains(ch)) continue;
      final got = i < u.length ? u[i] : '';
      final correct = got == ch;
      _pushCapped(charRecent.putIfAbsent(ch, () => <bool>[]), correct);
    }
  }

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

  /// Minimum reps a freshly-introduced item needs before another new item may
  /// be introduced — enforces "one new thing at a time, let it settle first"
  /// (Koch). Prevents the flood where high overall accuracy (inflated by many
  /// mastered items) opens the floodgates to several new items at once.
  static const int kSettleReps = 6;

  /// Whether the next locked item may be introduced now. Requires BOTH:
  ///  1. overall recent accuracy is healthy (don't pile onto a struggler), and
  ///  2. the most-recently-introduced item has "settled" — enough reps under it
  ///     and not struggling — so new material arrives one-at-a-time, not in a
  ///     burst.
  bool canIntroduceNew() {
    final active = states.values.where((s) => s.introduced).toList();
    if (active.isEmpty) return true; // nothing yet — always seed the first item

    // (1) Overall accuracy gate — use the (lower) promotion threshold so we
    // don't over-drill before adding the next item.
    var hits = 0, total = 0;
    for (final s in active) {
      hits += s.recentCorrect.where((c) => c).length;
      total += s.recentCorrect.length;
    }
    if (total > 0 && hits / total < config.promotionGate) return false;

    // (2) "Settling" gate: the least-practised introduced item must have had
    // real practice (>= kSettleReps) and not be struggling — so new material
    // arrives one at a time, not in a burst.
    final youngest =
        active.reduce((a, b) => a.reps <= b.reps ? a : b);
    if (youngest.reps < kSettleReps) return false;
    if (youngest.accuracy < config.promotionGate - 0.15) return false; // ~<70%

    return true;
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

    // Characters the learner is currently getting WRONG — measured per-character
    // across ALL items (so a fumble inside a word counts too, not just a solo
    // character). Their confusable neighbours get boosted so we interleave
    // discrimination practice on the exact pairs being mixed up.
    final confusablesToBoost = <String>{};
    for (final ch in charRecent.keys) {
      if ((charRecent[ch]?.length ?? 0) >= 2 &&
          charAccuracy(ch) < config.promotionGate) {
        confusablesToBoost.addAll(confusablesOf(ch));
      }
    }

    // 2. Weighted pick among introduced items, favouring due + weak items, and
    // boosting confusable neighbours of items being missed.
    String? best;
    double bestWeight = -1;
    for (final id in introducedIds) {
      final s = states[id];
      final overdue = s == null ? 0 : (repCounter - s.dueAtRep);
      // Only items at/after their due rep are eligible; if none are due yet,
      // still allow the most-overdue (least-negative) so we never stall.
      final dueBonus = overdue >= 0 ? 1.0 + overdue : 1.0 / (1 - overdue);
      final weakness = s == null ? 1.0 : (1.0 - s.accuracy);
      final confusableBonus = confusablesToBoost.contains(id) ? 1.6 : 1.0;
      // Small jitter breaks ties without an external clock.
      final weight = dueBonus *
          (0.5 + weakness) *
          confusableBonus *
          (0.85 + 0.3 * _rng.nextDouble());
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
