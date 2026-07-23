import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  group('adaptEffectiveWpm', () {
    test('ramps up on a strong session (fast + accurate)', () {
      final next = adaptEffectiveWpm(
          current: 12, itemsSeen: 20, accuracy: 0.95, medianLatencyMs: 400);
      expect(next, 13);
    });

    test('eases down when accuracy falls well below the gate', () {
      final next = adaptEffectiveWpm(
          current: 15, itemsSeen: 20, accuracy: 0.60, medianLatencyMs: 500);
      expect(next, 14);
    });

    test('holds when accurate but slow (not instant enough to speed up)', () {
      final next = adaptEffectiveWpm(
          current: 14, itemsSeen: 20, accuracy: 0.95, medianLatencyMs: 900);
      expect(next, 14);
    });

    test('holds in the middle band (ok accuracy, not clearly struggling)', () {
      final next = adaptEffectiveWpm(
          current: 14, itemsSeen: 20, accuracy: 0.82, medianLatencyMs: 900);
      expect(next, 14);
    });

    test('needs enough items before moving', () {
      final next = adaptEffectiveWpm(
          current: 12, itemsSeen: 3, accuracy: 1.0, medianLatencyMs: 300);
      expect(next, 12);
    });

    test('clamps to the max (never exceeds character speed)', () {
      final next = adaptEffectiveWpm(
          current: kMaxEffectiveWpm, itemsSeen: 20, accuracy: 1.0, medianLatencyMs: 300);
      expect(next, kMaxEffectiveWpm);
    });

    test('clamps to the min', () {
      final next = adaptEffectiveWpm(
          current: kMinEffectiveWpm, itemsSeen: 20, accuracy: 0.2, medianLatencyMs: 500);
      expect(next, kMinEffectiveWpm);
    });
  });

  test('AdaptiveProgress persists effectiveWpm (default for old records)', () {
    final p = AdaptiveProgress(effectiveWpm: 17);
    final loaded = AdaptiveProgress.fromJson(p.toJson());
    expect(loaded.effectiveWpm, 17);

    // Old blob without the key falls back to the starting speed.
    final old = AdaptiveProgress.fromJson({'totalReps': 5});
    expect(old.effectiveWpm, kStartEffectiveWpm);
  });
}
