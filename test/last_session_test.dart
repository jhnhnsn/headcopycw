// Verifies the data the home panel's "Last session" block renders from:
// unlocked ids resolve to curriculum display text, and the summary math holds.

import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/adaptive/curriculum.dart';
import 'package:head_copy_cw_trainer/adaptive/progress_store.dart';

void main() {
  test('unlocked ids resolve to curriculum display text for chips', () {
    // 'CQ' is stored by id (spaces collapse); its display text is 'CQ'.
    // Phrase ids collapse spaces, so verify a phrase round-trips to its text.
    final phrase = kCurriculum.firstWhere((c) => c.text.contains(' '));
    expect(kCurriculumById[phrase.id]?.text, phrase.text);

    // A plain character/word id maps to itself.
    expect(kCurriculumById['CQ']?.text, 'CQ');
  });

  test('last-session accuracy and unlocked count derive correctly', () {
    final s = SessionSummary(
      endedAtMs: 2000,
      durationSeconds: 300,
      itemsSeen: 20,
      correct: 18,
      medianLatencyMs: 410,
      unlockedIds: const ['C', 'Q', 'CQ'],
    );
    expect((s.accuracy * 100).round(), 90);
    expect(s.newItemsUnlocked, 3);
    expect(s.unlockedIds, ['C', 'Q', 'CQ']);
  });

  test('a session with no unlocks reports zero and an empty list', () {
    final s = SessionSummary(
      endedAtMs: 1,
      durationSeconds: 60,
      itemsSeen: 5,
      correct: 5,
      medianLatencyMs: 300,
    );
    expect(s.newItemsUnlocked, 0);
    expect(s.unlockedIds, isEmpty);
  });
}
