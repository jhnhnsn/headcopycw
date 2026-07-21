import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';

void main() {
  test('no nudge before anything in a tier has started', () {
    // Fresh scheduler: nothing introduced → nothing in the first tier started.
    final sched = SrsScheduler(rng: Random(1));
    expect(milestoneNudge(sched, kCurriculum), isNull);
  });

  test('nudge appears once a tier is partway, and NEVER names the next item', () {
    final sched = SrsScheduler(rng: Random(1));
    // Introduce the first several curriculum items (simulate partial progress).
    for (var i = 0; i < 6 && i < kCurriculum.length; i++) {
      sched.grade(id: kCurriculum[i].id, correct: true, latencyMs: 300);
    }

    final nudge = milestoneNudge(sched, kCurriculum);
    expect(nudge, isNotNull);

    // Find the next not-yet-introduced item — its text must NOT leak.
    final next = kCurriculum.firstWhere(
        (it) => !(sched.states[it.id]?.introduced ?? false));
    // The nudge is tier-level prose; it must not contain the next item's text
    // (avoid trivial single-letter false-negatives by checking word-ish items).
    if (next.text.length >= 2) {
      expect(nudge!.contains(next.text), isFalse,
          reason: 'nudge "$nudge" leaked next item "${next.text}"');
    }
  });

  test('no nudge once the whole curriculum is introduced', () {
    final sched = SrsScheduler(rng: Random(1));
    for (final it in kCurriculum) {
      sched.grade(id: it.id, correct: true, latencyMs: 300);
    }
    expect(milestoneNudge(sched, kCurriculum), isNull);
  });

  test('tierName never returns a specific item text', () {
    for (var t = 0; t <= 5; t++) {
      final name = tierName(t);
      expect(name.isNotEmpty, isTrue);
      // Names are generic category descriptions, not on-air tokens.
      expect(name, isNot(matches(RegExp(r'^[A-Z0-9/]+$'))));
    }
  });
}
