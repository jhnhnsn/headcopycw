// Simulates finishing the whole fixed curriculum and confirms the generator
// then supplies an endless stream of fresh, valid, non-persisted items —
// mirroring what AdaptivePage does once _curriculumExhausted is true.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/morse_data.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum_provider.dart';
import 'package:head_copy_cw_trainer/adaptive/generator.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';

void main() {
  test('after the curriculum is exhausted, the generator yields endless items',
      () {
    final curriculum = buildCurriculum('W1ABC');
    final sched = SrsScheduler(rng: Random(1));

    // Master every fixed item (fast + accurate).
    for (final it in curriculum) {
      for (var i = 0; i < 4; i++) {
        sched.grade(id: it.id, correct: true, latencyMs: 300);
      }
    }

    // "_nextLocked" equivalent: nothing left to introduce.
    bool anyLocked() => curriculum.any((it) {
          final st = sched.states[it.id];
          return st == null || !st.introduced;
        });
    expect(anyLocked(), isFalse, reason: 'curriculum should be exhausted');

    // Now generate a long tail and grade it; must stay valid and unbounded.
    final gen = CopyGenerator(seed: 1, myCallsign: 'W1ABC');
    for (var i = 0; i < 500; i++) {
      final item = gen.next();
      expect(isGeneratedId(item.id), isTrue);
      for (final ch in item.text.replaceAll(' ', '').replaceAll('/', '').split('')) {
        expect(kMorseCode.containsKey(ch), isTrue);
      }
      sched.grade(id: item.id, correct: true, latencyMs: 300);
    }

    // Progress counts still reflect ONLY the fixed curriculum (generated items
    // do not inflate the "unlocked" total).
    final summary = summarize(sched, curriculum: curriculum);
    expect(summary.unlocked, curriculum.length);
    expect(summary.total, curriculum.length);
  });

  test('the learner callsign is mastered as part of the curriculum', () {
    final curriculum = buildCurriculum('K9XYZ');
    final myId = '${kMyCallIdPrefix}K9XYZ';
    expect(curriculum.any((it) => it.id == myId), isTrue);
  });
}
