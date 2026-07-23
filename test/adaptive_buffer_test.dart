import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/srs.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  group('adaptBufferMs — ICR→copy-behind gate', () {
    test('stays 0 before the mastery gate (pure ICR phase)', () {
      final b = adaptBufferMs(
        current: 0,
        masteredCount: kBufferGateMasteredItems - 1,
        bufferedItems: 0,
        bufferedAccuracy: 1.0,
      );
      expect(b, 0);
    });

    test('introduces a small buffer once the gate opens', () {
      final b = adaptBufferMs(
        current: 0,
        masteredCount: kBufferGateMasteredItems,
        bufferedItems: 0,
        bufferedAccuracy: 1.0,
      );
      expect(b, kBufferStartMs);
    });
  });

  group('adaptBufferMs — grow/hold/ease on retention accuracy', () {
    test('grows while accurate with the buffer active', () {
      final b = adaptBufferMs(
        current: kBufferStartMs,
        masteredCount: 20,
        bufferedItems: 20,
        bufferedAccuracy: 0.95,
      );
      expect(b, kBufferStartMs + kBufferStepMs);
    });

    test('eases back when buffered accuracy drops', () {
      final b = adaptBufferMs(
        current: kBufferStartMs + 3 * kBufferStepMs,
        masteredCount: 20,
        bufferedItems: 20,
        bufferedAccuracy: 0.60,
      );
      expect(b, kBufferStartMs + 2 * kBufferStepMs);
    });

    test('holds in the middle band', () {
      final b = adaptBufferMs(
        current: kBufferStartMs + kBufferStepMs,
        masteredCount: 20,
        bufferedItems: 20,
        bufferedAccuracy: 0.82,
      );
      expect(b, kBufferStartMs + kBufferStepMs);
    });

    test('holds on thin buffered evidence', () {
      final b = adaptBufferMs(
        current: kBufferStartMs,
        masteredCount: 20,
        bufferedItems: 3,
        bufferedAccuracy: 1.0,
      );
      expect(b, kBufferStartMs);
    });

    test('never exceeds the ceiling (a word or two behind)', () {
      final b = adaptBufferMs(
        current: kBufferMaxMs,
        masteredCount: 20,
        bufferedItems: 20,
        bufferedAccuracy: 1.0,
      );
      expect(b, kBufferMaxMs);
    });

    test('easing never drops below the introductory buffer', () {
      final b = adaptBufferMs(
        current: kBufferStartMs,
        masteredCount: 20,
        bufferedItems: 20,
        bufferedAccuracy: 0.10,
      );
      expect(b, kBufferStartMs);
    });
  });

  test('AdaptiveProgress persists bufferMs (default 0 for old records)', () {
    final p = AdaptiveProgress(bufferMs: 700);
    expect(AdaptiveProgress.fromJson(p.toJson()).bufferMs, 700);
    expect(AdaptiveProgress.fromJson({'totalReps': 1}).bufferMs, 0);
  });
}
