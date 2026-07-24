import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  group('elapsedTargetMs', () {
    test('uses the fallback per-char when there is no history', () {
      final t = elapsedTargetMs(history: const [], charCount: 1, fallbackPerCharMs: 550);
      expect(t, greaterThan(0));
      // Single char: perChar × (0.6 + 0.4) = perChar. Floored at 1200.
      expect(t, 1200);
    });

    test('adapts to the learner median × margin', () {
      // Median 400ms, margin 2.0 → perChar 800; single char total clamps to 1200.
      final slow = elapsedTargetMs(history: const [900, 950, 1000], charCount: 1, margin: 2.0);
      final fast = elapsedTargetMs(history: const [200, 220, 240], charCount: 1, margin: 2.0);
      expect(slow, greaterThan(fast));
    });

    test('respects the floor (typed ICR nudge)', () {
      // Very fast median but floor keeps it from going below the ICR target.
      final t = elapsedTargetMs(
          history: const [100, 100, 100], charCount: 1, margin: 1.0, floorMs: 550);
      // perChar floored to 550; single char → 550, but clamped up to 1200 min.
      expect(t, greaterThanOrEqualTo(550));
    });

    test('scales with character count', () {
      final one = elapsedTargetMs(history: const [400], charCount: 1, margin: 2.0);
      final five = elapsedTargetMs(history: const [400], charCount: 5, margin: 2.0);
      expect(five, greaterThan(one));
    });

    test('clamps to a sane maximum', () {
      final t = elapsedTargetMs(history: const [5000], charCount: 30, margin: 3.0);
      expect(t, lessThanOrEqualTo(15000));
    });
  });

  group('AdaptiveProgress history + paper', () {
    test('pushCapped keeps the last 30', () {
      final h = <int>[];
      for (var i = 0; i < 40; i++) {
        AdaptiveProgress.pushCapped(h, i);
      }
      expect(h.length, 30);
      expect(h.first, 10);
      expect(h.last, 39);
    });

    test('recognition-time history round-trips through JSON', () {
      final p = AdaptiveProgress()..recentTypedMs.addAll([300, 400, 500]);
      final loaded = AdaptiveProgress.fromJson(p.toJson());
      expect(loaded.recentTypedMs, [300, 400, 500]);
    });

    test('old blobs default history to empty', () {
      final loaded = AdaptiveProgress.fromJson({'totalReps': 3});
      expect(loaded.recentTypedMs, isEmpty);
    });
  });
}
