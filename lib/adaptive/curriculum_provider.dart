/// Composes the fixed [kCurriculum] with the learner's own callsign.
///
/// The user's callsign is the first thing you copy on the air, so — when set —
/// it's spliced into the curriculum EARLY (right after the core prosigns) as a
/// high-priority word item, ahead of the generic callsign-copy tier. With no
/// callsign set, the plain [kCurriculum] is returned unchanged.
library;

import 'curriculum.dart';

/// Id prefix for the learner's own callsign item, so it's recognisable in the
/// SRS state and progress views.
const String kMyCallIdPrefix = 'MYCALL:';

/// Builds the ordered curriculum for a learner with the given [callsign]
/// (already normalised/uppercased; '' means none). The callsign item is
/// inserted after the first handful of items so it's learned early but not
/// before the learner has any character footing.
List<CurriculumItem> buildCurriculum(String callsign) {
  if (callsign.isEmpty) return kCurriculum;

  final myCall = CurriculumItem(
    id: '$kMyCallIdPrefix$callsign',
    text: callsign,
    kind: ItemKind.word,
    tier: 1,
    // Prereqs are its component characters; if some aren't introduced yet by
    // the insertion point, the scheduler simply waits until they are.
    prereqs: _charsOf(callsign),
  );

  // Insert a little way in (after ~the first prosigns) rather than at index 0,
  // so the learner isn't asked to copy a whole call before knowing any letters.
  const insertAt = 12;
  final out = List<CurriculumItem>.of(kCurriculum);
  final idx = insertAt.clamp(0, out.length);
  // Guard against a duplicate id if the call happens to already be present.
  if (out.any((it) => it.id == myCall.id)) return kCurriculum;
  out.insert(idx, myCall);
  return out;
}

/// Lookup map for a composed curriculum.
Map<String, CurriculumItem> curriculumById(List<CurriculumItem> items) => {
      for (final it in items) it.id: it,
    };

List<String> _charsOf(String text) {
  final seen = <String>{};
  for (final ch in text.replaceAll(' ', '').split('')) {
    seen.add(ch);
  }
  return seen.toList();
}
