// Integration-style test: drive the real curriculum through the scheduler to
// verify the end-to-end adaptive behavior a learner would experience.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';

/// Runs one simulated session of [reps] presentations against a fresh
/// scheduler, using [answer] to decide (correct, latencyMs) for a given item id.
SrsScheduler _runSession(
  int reps,
  (bool, int) Function(String id) answer, {
  int seed = 42,
}) {
  final sched = SrsScheduler(rng: Random(seed));

  ({String id, List<String> prereqs})? nextLocked() {
    for (final it in kCurriculum) {
      final st = sched.states[it.id];
      if (st == null || !st.introduced) {
        return (id: it.id, prereqs: it.prereqs);
      }
    }
    return null;
  }

  for (var i = 0; i < reps; i++) {
    final introduced =
        sched.states.entries.where((e) => e.value.introduced).map((e) => e.key).toList();
    final pick = sched.pickNext(introducedIds: introduced, nextLockedItem: nextLocked());
    if (pick == null) break;
    final (correct, latency) = answer(pick);
    sched.grade(id: pick, correct: correct, latencyMs: latency);
  }
  return sched;
}

int _introducedCount(SrsScheduler s) =>
    s.states.values.where((st) => st.introduced).length;

void main() {
  test('a fast+accurate learner unlocks progressively through the curriculum', () {
    final sched = _runSession(400, (_) => (true, 300)); // always instant & right
    final unlocked = _introducedCount(sched);
    // Should have moved well past the first item but not necessarily the whole
    // curriculum (introduction is probabilistic and gated).
    expect(unlocked, greaterThan(8),
        reason: 'good learner should keep unlocking new items');
    // First curriculum item is always seeded.
    expect(sched.states.containsKey(kCurriculum.first.id), isTrue);
  });

  test('a struggling learner stalls near the start', () {
    // Always wrong → accuracy gate keeps the curriculum from advancing.
    final sched = _runSession(400, (_) => (false, 300));
    final unlocked = _introducedCount(sched);
    expect(unlocked, lessThanOrEqualTo(2),
        reason: 'poor accuracy should block new introductions');
  });

  test('an accurate-but-slow learner consolidates without racing ahead', () {
    // Correct but always over the ICR latency gate → items never "master",
    // so prereq-gated words/phrases stay locked behind their characters.
    final fast = _runSession(300, (_) => (true, 300));
    final slow = _runSession(300, (_) => (true, 900));
    expect(_introducedCount(slow), lessThan(_introducedCount(fast)),
        reason: 'slow recognition should gate progression vs. instant recognition');
  });

  test('unlock respects prerequisites: no word before its characters', () {
    final sched = _runSession(400, (_) => (true, 300));
    for (final it in kCurriculum) {
      final st = sched.states[it.id];
      if (st == null || !st.introduced) continue; // not reached yet
      for (final p in it.prereqs) {
        final pst = sched.states[p];
        expect(pst?.introduced, isTrue,
            reason: '"${it.id}" was introduced before its prereq "$p"');
      }
    }
  });
}
