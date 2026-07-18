import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';

void main() {
  test('fresh scheduler → everything locked', () {
    final s = summarize(SrsScheduler(rng: Random(1)));
    expect(s.total, kCurriculum.length);
    expect(s.unlocked, 0);
    expect(s.mastered, 0);
    expect(s.learning, 0);
    expect(s.locked, kCurriculum.length);
    expect(s.unlockedFraction, 0);
  });

  test('an introduced-but-weak item counts as learning, not mastered', () {
    final sched = SrsScheduler(rng: Random(1));
    // One rep, wrong → introduced but far from mastered.
    sched.grade(id: 'K', correct: false, latencyMs: 300);
    final s = summarize(sched);
    expect(s.unlocked, 1);
    expect(s.learning, 1);
    expect(s.mastered, 0);

    final progress = itemProgressList(sched);
    final k = progress.firstWhere((p) => p.item.id == 'K');
    expect(k.status, ItemStatus.learning);
    expect(k.reps, 1);
  });

  test('a fast+accurate item counts as mastered', () {
    final sched = SrsScheduler(rng: Random(1));
    for (var i = 0; i < 4; i++) {
      sched.grade(id: 'K', correct: true, latencyMs: 300);
    }
    final s = summarize(sched);
    expect(s.mastered, 1);
    expect(s.learning, 0);

    final k = itemProgressList(sched).firstWhere((p) => p.item.id == 'K');
    expect(k.status, ItemStatus.mastered);
    expect(k.accuracy, 1.0);
    expect(k.medianLatencyMs, 300);
  });

  test('itemProgressList covers the whole curriculum in order', () {
    final list = itemProgressList(SrsScheduler(rng: Random(1)));
    expect(list.length, kCurriculum.length);
    for (var i = 0; i < list.length; i++) {
      expect(list[i].item.id, kCurriculum[i].id);
    }
  });
}
