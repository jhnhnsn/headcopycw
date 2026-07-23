import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

SessionSummary _s({required int dur, required int target}) => SessionSummary(
      endedAtMs: 0,
      durationSeconds: dur,
      targetSeconds: target,
      itemsSeen: 10,
      correct: 8,
      medianLatencyMs: 400,
    );

void main() {
  test('a completed fixed-length session is a full bar (1.0)', () {
    expect(_s(dur: 300, target: 300).durationFraction, 1.0);
  });

  test('a session stopped early is the fraction it ran', () {
    expect(_s(dur: 150, target: 300).durationFraction, 0.5);
    expect(_s(dur: 60, target: 300).durationFraction, closeTo(0.2, 1e-9));
  });

  test('over-running (clock drift) clamps to 1.0', () {
    expect(_s(dur: 400, target: 300).durationFraction, 1.0);
  });

  test('unlimited sessions (no target) count as full', () {
    expect(_s(dur: 900, target: 0).durationFraction, 1.0);
  });

  test('targetSeconds round-trips through JSON (default 0 for old records)', () {
    final j = _s(dur: 200, target: 300).toJson();
    expect(SessionSummary.fromJson(j).targetSeconds, 300);
    // Old record without the key defaults to 0 → treated as unlimited/full.
    final old = {
      'endedAtMs': 0, 'durationSeconds': 200, 'itemsSeen': 10,
      'correct': 8, 'medianLatencyMs': 400,
    };
    final s = SessionSummary.fromJson(old);
    expect(s.targetSeconds, 0);
    expect(s.durationFraction, 1.0);
  });
}
