// Verifies progress survives a simulated restart the same way AdaptivePage
// loads/saves: immediate flush after each graded item, then fresh objects
// reload from disk.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  test('grades persist across a simulated hot restart', () async {
    final dir = await Directory.systemTemp.createTemp('persist_check');
    final file = File('${dir.path}/adaptive_progress.json');

    // Session 1: fresh, grade two items, flush immediately after each.
    var store = ProgressStore(file);
    var progress = await store.load();
    var sched =
        SrsScheduler(states: progress.itemStates, repCounter: progress.totalReps);

    sched.grade(id: 'C', correct: true, latencyMs: 300);
    progress.totalReps = sched.repCounter;
    await store.flush(progress);

    sched.grade(id: 'Q', correct: true, latencyMs: 300);
    progress.totalReps = sched.repCounter;
    await store.flush(progress);

    expect(await file.exists(), isTrue);
    final reps1 = sched.repCounter;

    // Simulate hot restart: brand-new objects reload from disk.
    store = ProgressStore(file);
    progress = await store.load();
    sched =
        SrsScheduler(states: progress.itemStates, repCounter: progress.totalReps);

    expect(sched.states.containsKey('C'), isTrue);
    expect(sched.states.containsKey('Q'), isTrue);
    expect(sched.states['C']!.reps, 1);
    expect(sched.states['Q']!.reps, 1);
    expect(sched.repCounter, reps1);

    await dir.delete(recursive: true);
  });
}
