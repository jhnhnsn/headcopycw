import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/morse_data.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum_provider.dart';
import 'package:head_copy_cw_trainer/adaptive/generator.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_stats.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';

void main() {
  group('buildCurriculum', () {
    test('no callsign → identical to the fixed curriculum', () {
      expect(buildCurriculum(''), same(kCurriculum));
    });

    test('a callsign is injected exactly once, early, with char prereqs', () {
      final list = buildCurriculum('W1ABC');
      final mine = list.where((c) => c.id == '${kMyCallIdPrefix}W1ABC').toList();
      expect(mine.length, 1, reason: 'callsign appears exactly once');
      final item = mine.first;
      expect(item.text, 'W1ABC');

      // Injected early (within the first ~15 items).
      final idx = list.indexWhere((c) => c.id == item.id);
      expect(idx, lessThan(15));

      // Prereqs are its component characters, all encodable.
      for (final p in item.prereqs) {
        expect(kMorseCode.containsKey(p), isTrue);
        expect('W1ABC'.contains(p), isTrue);
      }

      // Total is exactly one longer than the fixed curriculum.
      expect(list.length, kCurriculum.length + 1);
    });

    test('every composed item still encodes and has unique ids', () {
      final list = buildCurriculum('K9XYZ');
      final ids = list.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final it in list) {
        for (final ch in it.text.replaceAll(' ', '').replaceAll('/', '').split('')) {
          expect(kMorseCode.containsKey(ch), isTrue);
        }
      }
    });
  });

  group('progress isolation from generated items', () {
    test('summarize/itemProgressList ignore generated ids', () {
      final sched = SrsScheduler(rng: Random(1));
      // Master a real curriculum item.
      for (var i = 0; i < 4; i++) {
        sched.grade(id: 'K', correct: true, latencyMs: 300);
      }
      // Grade a bunch of generated items — these must NOT inflate counts.
      final gen = CopyGenerator(seed: 1);
      for (var i = 0; i < 20; i++) {
        sched.grade(id: gen.next().id, correct: true, latencyMs: 300);
      }

      final summary = summarize(sched);
      // Only the real 'K' counts as unlocked.
      expect(summary.unlocked, 1);
      expect(summary.total, kCurriculum.length);

      // The item map contains only curriculum items, never GEN: ones.
      final map = itemProgressList(sched);
      expect(map.any((p) => isGeneratedId(p.item.id)), isFalse);
    });

    test('composed-curriculum summarize counts the callsign item', () {
      final list = buildCurriculum('W1ABC');
      final sched = SrsScheduler(rng: Random(1));
      for (var i = 0; i < 4; i++) {
        sched.grade(id: '${kMyCallIdPrefix}W1ABC', correct: true, latencyMs: 300);
      }
      final summary = summarize(sched, curriculum: list);
      expect(summary.total, list.length);
      expect(summary.unlocked, 1);
    });
  });
}
