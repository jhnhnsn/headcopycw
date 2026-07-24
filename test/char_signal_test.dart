import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  group('recordCharOutcomes (per-character diff)', () {
    test('scores each character position correct/incorrect', () {
      final sched = SrsScheduler(rng: Random(1));
      // Target SOS, typed HOS → position 0 wrong (S), 1 right (O), 2 right (S).
      sched.recordCharOutcomes('SOS', 'HOS');
      // S appears at positions 0 (wrong) and 2 (right) → 1/2 = 0.5.
      expect(sched.charAccuracy('S'), closeTo(0.5, 1e-9));
      expect(sched.charAccuracy('O'), 1.0);
    });

    test('a missing/short answer marks the unreached chars wrong', () {
      final sched = SrsScheduler(rng: Random(1));
      sched.recordCharOutcomes('CAT', 'C'); // only C typed
      expect(sched.charAccuracy('C'), 1.0);
      expect(sched.charAccuracy('A'), 0.0);
      expect(sched.charAccuracy('T'), 0.0);
    });

    test('ignores spaces and punctuation positions gracefully', () {
      final sched = SrsScheduler(rng: Random(1));
      sched.recordCharOutcomes('UR RST', 'UR RST');
      expect(sched.charAccuracy('U'), 1.0);
      expect(sched.charAccuracy('R'), 1.0);
      expect(sched.charAccuracy('T'), 1.0);
    });
  });

  test('a character fumbled INSIDE a word drives confusable resurfacing', () {
    final sched = SrsScheduler(rng: Random(3));
    // Repeatedly miss the S inside a word by typing H for it. S and H are both
    // known/strong as standalone items; H and O are equally strong.
    for (var i = 0; i < 8; i++) {
      sched.grade(id: 'H', correct: true, latencyMs: 300);
      sched.grade(id: 'O', correct: true, latencyMs: 300);
      // Word "SO" typed as "HO" → S wrong inside the word.
      sched.recordCharOutcomes('SO', 'HO');
    }
    expect(sched.charAccuracy('S'), lessThan(sched.config.promotionGate));

    var hCount = 0, oCount = 0;
    for (var i = 0; i < 1000; i++) {
      final pick =
          sched.pickNext(introducedIds: const ['H', 'O'], nextLockedItem: null);
      if (pick == 'H') hCount++;
      if (pick == 'O') oCount++;
    }
    // H (confusable with the word-internal S miss) beats the unrelated O.
    expect(hCount, greaterThan(oCount),
        reason: 'word-internal char miss should drive confusable practice');
  });

  test('charRecent round-trips through JSON', () {
    final p = AdaptiveProgress();
    p.charRecent['S'] = [true, false, true];
    p.charRecent['E'] = [false];
    final loaded = AdaptiveProgress.fromJson(p.toJson());
    expect(loaded.charRecent['S'], [true, false, true]);
    expect(loaded.charRecent['E'], [false]);
    // Old records without the key default to empty.
    expect(AdaptiveProgress.fromJson({'totalReps': 1}).charRecent, isEmpty);
  });
}
