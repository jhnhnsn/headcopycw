import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/morse_data.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  group('ItemState gating', () {
    test('mastered requires both accuracy and latency gates', () {
      const cfg = SrsConfig();
      final s = ItemState(id: 'K');
      // Fast + accurate → mastered after enough evidence.
      for (var i = 0; i < 4; i++) {
        s.recentCorrect.add(true);
        s.recentLatencyMs.add(300);
      }
      expect(s.isMastered(cfg), isTrue);

      // Accurate but slow → NOT mastered (still consciously decoding).
      final slow = ItemState(id: 'M');
      for (var i = 0; i < 4; i++) {
        slow.recentCorrect.add(true);
        slow.recentLatencyMs.add(900);
      }
      expect(slow.accuracy, 1.0);
      expect(slow.isMastered(cfg), isFalse);

      // Fast but inaccurate → NOT mastered.
      final wrong = ItemState(id: 'R');
      for (var i = 0; i < 4; i++) {
        wrong.recentCorrect.add(i.isEven);
        wrong.recentLatencyMs.add(300);
      }
      expect(wrong.isMastered(cfg), isFalse);
    });

    test('median latency is robust to a single outlier', () {
      final s = ItemState(id: 'K');
      s.recentLatencyMs.addAll([300, 320, 5000]);
      expect(s.medianLatencyMs, 320);
    });
  });

  group('grade()', () {
    test('correct+fast promotes box; incorrect demotes; correct+slow holds', () {
      final sched = SrsScheduler(rng: Random(1));
      // Fast correct answers promote.
      sched.grade(id: 'K', correct: true, latencyMs: 300);
      sched.grade(id: 'K', correct: true, latencyMs: 300);
      final promoted = sched.states['K']!.box;
      expect(promoted, greaterThan(0));

      // A slow-but-correct answer holds the box.
      final before = sched.states['K']!.box;
      sched.grade(id: 'K', correct: true, latencyMs: 900);
      expect(sched.states['K']!.box, before);

      // An incorrect answer demotes.
      sched.grade(id: 'K', correct: false, latencyMs: 300);
      expect(sched.states['K']!.box, lessThan(before));
    });

    test('dueAtRep advances by the box interval', () {
      final sched = SrsScheduler(rng: Random(1));
      sched.repCounter = 10;
      sched.grade(id: 'K', correct: true, latencyMs: 300); // box 0 -> 1
      // box 1 interval == kBoxIntervals[1]
      expect(sched.states['K']!.dueAtRep, 10 + kBoxIntervals[1]);
    });
  });

  group('pickNext()', () {
    test('seeds the first locked item when nothing is introduced', () {
      final sched = SrsScheduler(rng: Random(1));
      final pick = sched.pickNext(
        introducedIds: const [],
        nextLockedItem: (id: 'K', prereqs: const []),
      );
      expect(pick, 'K');
    });

    test('does not introduce a new item whose prereqs are unmet', () {
      final sched = SrsScheduler(rng: Random(1));
      // 'CQ' requires C and Q mastered; neither exists → never introduced.
      // Introduce K so there IS a fallback to pick.
      sched.grade(id: 'K', correct: true, latencyMs: 300);
      var sawLocked = false;
      for (var i = 0; i < 200; i++) {
        final pick = sched.pickNext(
          introducedIds: const ['K'],
          nextLockedItem: (id: 'CQ', prereqs: const ['C', 'Q']),
        );
        if (pick == 'CQ') sawLocked = true;
      }
      expect(sawLocked, isFalse);
    });

    test('introduces a new item once prereqs are mastered', () {
      final sched = SrsScheduler(rng: Random(3));
      // Master C and Q (fast + accurate, and enough reps to "settle").
      for (final id in ['C', 'Q']) {
        for (var i = 0; i < 8; i++) {
          sched.grade(id: id, correct: true, latencyMs: 300);
        }
      }
      var sawLocked = false;
      for (var i = 0; i < 200; i++) {
        final pick = sched.pickNext(
          introducedIds: const ['C', 'Q'],
          nextLockedItem: (id: 'CQ', prereqs: const ['C', 'Q']),
        );
        if (pick == 'CQ') sawLocked = true;
      }
      expect(sawLocked, isTrue);
    });

    test('promotion gate is lower than the mastery gate (decoupled)', () {
      // Research: the "add the next item" bar should be lower than "this word's
      // letters are solid". Confirms the two knobs are separate.
      expect(kPromotionGate, lessThan(kAccuracyGate));
      expect(kPromotionGate, closeTo(0.85, 0.001));
    });

    test('does not introduce new material while overall accuracy is poor', () {
      final sched = SrsScheduler(rng: Random(5));
      // Master prereqs so only the accuracy gate is at play...
      for (final id in ['C', 'Q']) {
        for (var i = 0; i < 5; i++) {
          sched.grade(id: id, correct: true, latencyMs: 300);
        }
      }
      // ...then tank overall accuracy on another introduced item.
      for (var i = 0; i < 8; i++) {
        sched.grade(id: 'K', correct: false, latencyMs: 300);
      }
      var sawLocked = false;
      for (var i = 0; i < 200; i++) {
        final pick = sched.pickNext(
          introducedIds: const ['C', 'Q', 'K'],
          nextLockedItem: (id: 'CQ', prereqs: const ['C', 'Q']),
        );
        if (pick == 'CQ') sawLocked = true;
      }
      expect(sawLocked, isFalse, reason: 'accuracy gate should block new items');
    });

    test('a brand-new item blocks further introductions until it settles', () {
      final sched = SrsScheduler(rng: Random(9));
      // A well-established base (plenty of reps, all correct).
      for (final id in ['C', 'Q']) {
        for (var i = 0; i < 8; i++) {
          sched.grade(id: id, correct: true, latencyMs: 300);
        }
      }
      // Introduce one new item with only a couple of reps (brand new).
      for (var i = 0; i < 2; i++) {
        sched.grade(id: 'D', correct: true, latencyMs: 300);
      }
      // Even though overall accuracy is perfect, the youngest item (D, 2 reps)
      // hasn't settled → no further new item should be introduced yet.
      var sawLocked = false;
      for (var i = 0; i < 200; i++) {
        final pick = sched.pickNext(
          introducedIds: const ['C', 'Q', 'D'],
          nextLockedItem: (id: 'E', prereqs: const []),
        );
        if (pick == 'E') sawLocked = true;
      }
      expect(sawLocked, isFalse,
          reason: 'must not stack a new item on a brand-new one');

      // Once D has enough reps under it, the next item may come.
      for (var i = 0; i < 6; i++) {
        sched.grade(id: 'D', correct: true, latencyMs: 300);
      }
      var sawAfter = false;
      for (var i = 0; i < 200; i++) {
        final pick = sched.pickNext(
          introducedIds: const ['C', 'Q', 'D'],
          nextLockedItem: (id: 'E', prereqs: const []),
        );
        if (pick == 'E') sawAfter = true;
      }
      expect(sawAfter, isTrue, reason: 'after settling, a new item is allowed');
    });

    test('favours the weakest/most-overdue introduced item', () {
      final sched = SrsScheduler(rng: Random(7));
      // 'A' strong, 'B' weak. No new item available.
      for (var i = 0; i < 6; i++) {
        sched.grade(id: 'A', correct: true, latencyMs: 300);
      }
      for (var i = 0; i < 6; i++) {
        sched.grade(id: 'B', correct: false, latencyMs: 300);
      }
      var bCount = 0;
      for (var i = 0; i < 300; i++) {
        final pick =
            sched.pickNext(introducedIds: const ['A', 'B'], nextLockedItem: null);
        if (pick == 'B') bCount++;
      }
      expect(bCount, greaterThan(150), reason: 'weak item should dominate');
    });

    test('resurfaces the confusable neighbour of a missed character', () {
      // S (...) is being missed occasionally; H (....) is its confusable
      // neighbour, O is unrelated — both otherwise equally strong. H should be
      // resurfaced more than O for discrimination practice. The per-character
      // signal (recordCharOutcomes) is how the real app feeds this, including
      // for solo characters.
      final sched = SrsScheduler(rng: Random(11));
      for (var i = 0; i < 8; i++) {
        // Solo S copied wrong (~75%) → feeds the char signal below the gate.
        sched.recordCharOutcomes('S', i < 6 ? 'S' : 'H');
        sched.grade(id: 'H', correct: true, latencyMs: 300);
        sched.grade(id: 'O', correct: true, latencyMs: 300);
      }
      expect(sched.charAccuracy('S'), lessThan(sched.config.promotionGate));
      var hCount = 0, oCount = 0;
      for (var i = 0; i < 1000; i++) {
        final pick = sched.pickNext(
            introducedIds: const ['H', 'O'], nextLockedItem: null);
        if (pick == 'H') hCount++;
        if (pick == 'O') oCount++;
      }
      // H (confusable with the missed S) should beat the equally-strong but
      // unrelated O.
      expect(hCount, greaterThan(oCount),
          reason: 'confusable neighbour should be resurfaced over an unrelated item');
    });
  });

  group('curriculum', () {
    test('every item text encodes via kMorseCode', () {
      for (final it in kCurriculum) {
        for (final ch in it.text.replaceAll(' ', '').split('')) {
          expect(kMorseCode.containsKey(ch), isTrue,
              reason: '"${it.text}" has unencodable char "$ch"');
        }
      }
    });

    test('word/phrase prereqs are introduced earlier than the item', () {
      final indexById = <String, int>{};
      for (var i = 0; i < kCurriculum.length; i++) {
        indexById[kCurriculum[i].id] = i;
      }
      for (var i = 0; i < kCurriculum.length; i++) {
        final it = kCurriculum[i];
        for (final p in it.prereqs) {
          expect(indexById[p], isNotNull,
              reason: 'prereq "$p" of "${it.id}" missing from curriculum');
          expect(indexById[p]! < i, isTrue,
              reason: 'prereq "$p" must come before "${it.id}"');
        }
      }
    });

    test('ids are unique', () {
      final ids = kCurriculum.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('ProgressStore', () {
    test('round-trips item states and sessions', () async {
      final dir = await Directory.systemTemp.createTemp('adaptive_test');
      final store = ProgressStore(File('${dir.path}/progress.json'));

      final prog = AdaptiveProgress(totalReps: 42);
      final st = ItemState(id: 'K', box: 3, reps: 10, dueAtRep: 50);
      st.recentCorrect.addAll([true, false, true]);
      st.recentLatencyMs.addAll([300, 400, 350]);
      prog.itemStates['K'] = st;
      prog.sessions.add(SessionSummary(
        endedAtMs: 123,
        durationSeconds: 300,
        itemsSeen: 20,
        correct: 18,
        medianLatencyMs: 420,
        unlockedIds: const ['C', 'Q'],
      ));

      await store.flush(prog);
      final loaded = await store.load();

      expect(loaded.totalReps, 42);
      expect(loaded.itemStates['K']!.box, 3);
      expect(loaded.itemStates['K']!.recentCorrect, [true, false, true]);
      expect(loaded.itemStates['K']!.recentLatencyMs, [300, 400, 350]);
      expect(loaded.sessions.length, 1);
      expect(loaded.sessions.first.correct, 18);
      expect(loaded.sessions.first.unlockedIds, ['C', 'Q']);
      expect(loaded.sessions.first.newItemsUnlocked, 2);

      await dir.delete(recursive: true);
    });

    test('load() returns empty on missing/corrupt file', () async {
      final dir = await Directory.systemTemp.createTemp('adaptive_test');
      final missing = ProgressStore(File('${dir.path}/nope.json'));
      expect((await missing.load()).itemStates, isEmpty);

      final bad = File('${dir.path}/bad.json');
      await bad.writeAsString('{not valid json');
      expect((await ProgressStore(bad).load()).itemStates, isEmpty);

      await dir.delete(recursive: true);
    });
  });
}
