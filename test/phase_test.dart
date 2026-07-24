import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';

void main() {
  test('a fresh learner is in the recognition phase', () {
    final sched = SrsScheduler(rng: Random(1));
    expect(currentPhase(sched, kCurriculum), LearningPhase.recognition);
  });

  test('recognition → copy behind once the mastery gate is reached', () {
    final sched = SrsScheduler(rng: Random(1));
    // Master the first kBufferGateMasteredItems curriculum items.
    for (final it in kCurriculum.take(kBufferGateMasteredItems)) {
      for (var i = 0; i < 4; i++) {
        sched.grade(id: it.id, correct: true, latencyMs: 300);
      }
    }
    expect(currentPhase(sched, kCurriculum), LearningPhase.copyBehind);
  });

  test('one short of the gate is still recognition', () {
    final sched = SrsScheduler(rng: Random(1));
    for (final it in kCurriculum.take(kBufferGateMasteredItems - 1)) {
      for (var i = 0; i < 4; i++) {
        sched.grade(id: it.id, correct: true, latencyMs: 300);
      }
    }
    expect(currentPhase(sched, kCurriculum), LearningPhase.recognition);
  });

  test('on the air once every item is introduced', () {
    final sched = SrsScheduler(rng: Random(1));
    for (final it in kCurriculum) {
      sched.grade(id: it.id, correct: true, latencyMs: 300);
    }
    expect(currentPhase(sched, kCurriculum), LearningPhase.onTheAir);
  });

  test('phase enum order matches the stepper (index = progression)', () {
    expect(LearningPhase.recognition.index, 0);
    expect(LearningPhase.copyBehind.index, 1);
    expect(LearningPhase.onTheAir.index, 2);
  });
}
