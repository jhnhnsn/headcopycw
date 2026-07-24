// End-to-end multi-session simulation. This is the app's highest-risk path:
// progress must serialize to disk, survive a kill/restart, and keep advancing —
// exactly where past bugs lived (stuck-on-C, lost progress). It mirrors the real
// AdaptivePage loop:
//   pickNext -> grade -> recordCharOutcomes -> immediate flush   (per item)
//   adaptEffectiveWpm + adaptBufferMs + SessionSummary            (per session)
//   reload with FRESH objects from disk                           (per restart)
// across several sessions, asserting the cross-session behavior a learner sees.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum_provider.dart';

/// One session against a scheduler already loaded from [progress].
/// Returns the SessionSummary-relevant aggregates and mutates [progress].
/// [answer] returns (correct, latencyMs) for a given item id — the learner model.
Future<({int seen, int correct, int median, List<String> unlocked})> _runSession(
  SrsScheduler sched,
  AdaptiveProgress progress,
  List<CurriculumItem> curriculum,
  Map<String, CurriculumItem> byId,
  int reps,
  (bool, int) Function(String id) answer,
  ProgressStore store,
) async {
  var seen = 0, correct = 0;
  final lat = <int>[];
  final unlocked = <String>[];

  ({String id, List<String> prereqs})? nextLocked() {
    for (final it in curriculum) {
      final st = sched.states[it.id];
      if (st == null || !st.introduced) {
        return (id: it.id, prereqs: it.prereqs);
      }
    }
    return null;
  }

  for (var i = 0; i < reps; i++) {
    final introduced = sched.states.entries
        .where((e) => e.value.introduced)
        .map((e) => e.key)
        .toList();
    final wasIntroduced = introduced.toSet();
    final pick =
        sched.pickNext(introducedIds: introduced, nextLockedItem: nextLocked());
    if (pick == null) break;

    // Was this pick a brand-new introduction this rep?
    final newlyIntroduced = !wasIntroduced.contains(pick) &&
        (sched.states[pick]?.introduced ?? false);
    if (newlyIntroduced) unlocked.add(pick);

    final (isCorrect, latency) = answer(pick);
    final target = byId[pick]?.text ?? pick;
    // Simulate a typed answer: correct -> target, wrong -> a mangled copy.
    final typed = isCorrect ? target : _mangle(target);
    sched.grade(id: pick, correct: isCorrect, latencyMs: latency);
    sched.recordCharOutcomes(target, typed);

    seen++;
    if (isCorrect) correct++;
    lat.add(latency);
    AdaptiveProgress.pushCapped(progress.recentTypedMs, latency);

    // Immediate flush after each graded item (as the real app does).
    progress.totalReps = sched.repCounter;
    await store.flush(progress);
  }

  lat.sort();
  final median = lat.isEmpty ? 0 : lat[lat.length ~/ 2];
  return (seen: seen, correct: correct, median: median, unlocked: unlocked);
}

String _mangle(String s) {
  if (s.isEmpty) return 'X';
  // Flip the first char to something else so it grades wrong per-position too.
  final first = s[0] == 'X' ? 'Y' : 'X';
  return first + s.substring(1);
}

int _introduced(SrsScheduler s) =>
    s.states.values.where((st) => st.introduced).length;

void main() {
  late Directory dir;
  late ProgressStore store;
  late List<CurriculumItem> curriculum;
  late Map<String, CurriculumItem> byId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('multisession');
    store = ProgressStore(File('${dir.path}/adaptive_progress.json'));
    curriculum = buildCurriculum('');
    byId = curriculumById(curriculum);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Finalize a session exactly like AdaptivePage._finalizeSession: append a
  /// SessionSummary, then adapt effective speed and the copy-behind buffer.
  void finalize(
    AdaptiveProgress progress,
    SrsScheduler sched,
    ({int seen, int correct, int median, List<String> unlocked}) s,
  ) {
    if (s.seen == 0) return;
    final acc = s.correct / s.seen;
    progress.sessions.add(SessionSummary(
      endedAtMs: progress.sessions.length, // deterministic stand-in for clock
      durationSeconds: 300,
      targetSeconds: 300,
      itemsSeen: s.seen,
      correct: s.correct,
      medianLatencyMs: s.median,
      unlockedIds: List.of(s.unlocked),
    ));
    progress.effectiveWpm = adaptEffectiveWpm(
      current: progress.effectiveWpm,
      itemsSeen: s.seen,
      accuracy: acc,
      medianLatencyMs: s.median,
    );
    final mastered = summarize(sched, curriculum: curriculum).mastered;
    progress.bufferMs = adaptBufferMs(
      current: progress.bufferMs,
      masteredCount: mastered,
      bufferedItems: 0,
      bufferedAccuracy: 1.0,
    );
  }

  /// Reload fresh objects from disk, the way the app does after a kill/restart.
  Future<(AdaptiveProgress, SrsScheduler)> reload(int seed) async {
    final progress = await store.load();
    final sched = SrsScheduler(
      states: progress.itemStates,
      charRecent: progress.charRecent,
      repCounter: progress.totalReps,
      rng: Random(seed),
    );
    return (progress, sched);
  }

  test('progress accumulates & continues to unlock across reload boundaries',
      () async {
    final introducedProgression = <int>[];
    final repsProgression = <int>[];

    for (var session = 0; session < 6; session++) {
      final (progress, sched) = await reload(100 + session);
      // A strong learner: always correct, instant.
      final s = await _runSession(
          sched, progress, curriculum, byId, 60, (_) => (true, 300), store);
      finalize(progress, sched, s);
      await store.flush(progress);

      introducedProgression.add(_introduced(sched));
      repsProgression.add(sched.repCounter);
    }

    // 1. Reps strictly increase across sessions (nothing reset).
    for (var i = 1; i < repsProgression.length; i++) {
      expect(repsProgression[i], greaterThan(repsProgression[i - 1]),
          reason:
              'session ${i + 1} should continue rep count, got $repsProgression');
    }
    // 2. Introduced-item count is monotonic non-decreasing and grows overall.
    for (var i = 1; i < introducedProgression.length; i++) {
      expect(introducedProgression[i],
          greaterThanOrEqualTo(introducedProgression[i - 1]),
          reason: 'unlocks should never go backward, got $introducedProgression');
    }
    expect(introducedProgression.last, greaterThan(introducedProgression.first),
        reason: 'a strong learner should unlock more over time');

    // 3. Six sessions recorded on disk.
    final reloaded = await store.load();
    expect(reloaded.sessions.length, 6);
  });

  test('effective speed ramps up for a strong learner and persists', () async {
    int? firstWpm;
    int? lastWpm;

    for (var session = 0; session < 6; session++) {
      final (progress, sched) = await reload(session);
      firstWpm ??= progress.effectiveWpm;
      final s = await _runSession(
          sched, progress, curriculum, byId, 60, (_) => (true, 250), store);
      finalize(progress, sched, s);
      await store.flush(progress);
      lastWpm = progress.effectiveWpm;
    }

    expect(firstWpm, kStartEffectiveWpm);
    expect(lastWpm, greaterThan(firstWpm!),
        reason: 'strong sessions should ramp effective WPM up');
    expect(lastWpm, lessThanOrEqualTo(kMaxEffectiveWpm),
        reason: 'never exceeds the fixed character speed');
    // Persisted value matches what a fresh load sees.
    final reloaded = await store.load();
    expect(reloaded.effectiveWpm, lastWpm);
  });

  test('a struggling learner does not ramp speed or unlock much, across sessions',
      () async {
    for (var session = 0; session < 5; session++) {
      final (progress, sched) = await reload(session);
      // Always wrong.
      final s = await _runSession(
          sched, progress, curriculum, byId, 60, (_) => (false, 400), store);
      finalize(progress, sched, s);
      await store.flush(progress);
    }

    final reloaded = await store.load();
    final sched =
        SrsScheduler(states: reloaded.itemStates, repCounter: reloaded.totalReps);
    expect(_introduced(sched), lessThanOrEqualTo(2),
        reason: 'poor accuracy should block introductions across sessions too');
    expect(reloaded.effectiveWpm, lessThanOrEqualTo(kStartEffectiveWpm),
        reason: 'failing sessions must not ramp speed up');
  });

  test('buffer stays 0 until enough items are mastered, then can unlock',
      () async {
    // Strong learner over many sessions -> should eventually master enough items
    // that the copy-behind buffer leaves zero.
    for (var session = 0; session < 20; session++) {
      final (progress, sched) = await reload(session);
      final s = await _runSession(
          sched, progress, curriculum, byId, 80, (_) => (true, 250), store);
      finalize(progress, sched, s);
      await store.flush(progress);
    }

    final reloaded = await store.load();
    final sched =
        SrsScheduler(states: reloaded.itemStates, repCounter: reloaded.totalReps);
    final mastered = summarize(sched, curriculum: curriculum).mastered;
    expect(mastered, greaterThan(0), reason: 'strong learner should master items');
    if (mastered >= kBufferGateMasteredItems) {
      expect(reloaded.bufferMs, greaterThan(0),
          reason: 'past the mastery gate the copy-behind buffer should engage');
    } else {
      expect(reloaded.bufferMs, 0,
          reason: 'below the gate the buffer must stay disabled');
    }
  });
}
