/// Frequency-ordered curriculum for the adaptive "Copy" mode.
///
/// Ordering follows the research: *CW-on-air first*. The learner meets the
/// highest-payoff real material immediately — the prosigns, callsign fragments,
/// and formulaic exchange chunks that dominate an actual QSO — then broadens to
/// common English. Items are introduced in [kCurriculum] order, but only once
/// their prerequisite items are mastered (see [SrsScheduler.prereqsMet]).
///
/// A word/phrase's prerequisites are the *characters* it is built from, so the
/// learner always has instant character recognition before being asked to hear
/// a whole word as a single sound-shape (dual-route: sublexical decoding must
/// be reliable before the lexical/whole-word route can form).
library;

import '../morse_data.dart';

enum ItemKind {
  /// A single character or single-character prosign.
  character,

  /// A single real word or abbreviation copied as one sound-shape.
  word,

  /// A short multi-token formulaic phrase (e.g. "UR RST 599").
  phrase,
}

/// One unit the learner is trained to recognise.
class CurriculumItem {
  /// Stable id, used as the SRS key. Equals [text] for characters/words; for
  /// phrases it's the text with spaces collapsed so it stays a valid map key.
  final String id;

  /// The text sent in Morse and shown on reveal (uppercase, on-air form).
  final String text;

  final ItemKind kind;

  /// 1-based tier, for display/grouping only. Introduction order is list order.
  final int tier;

  /// Ids of items that must be mastered before this one may be introduced.
  /// For words/phrases these are the component characters.
  final List<String> prereqs;

  const CurriculumItem({
    required this.id,
    required this.text,
    required this.kind,
    required this.tier,
    required this.prereqs,
  });
}

String _idFor(String text) => text.replaceAll(' ', '_');

/// Component characters of [text] that exist in the Morse table, as prereq ids.
List<String> _charPrereqs(String text) {
  final seen = <String>{};
  for (final ch in text.replaceAll(' ', '').split('')) {
    if (kMorseCode.containsKey(ch)) seen.add(ch);
  }
  return seen.toList();
}

CurriculumItem _char(String c, int tier) =>
    CurriculumItem(id: c, text: c, kind: ItemKind.character, tier: tier, prereqs: const []);

CurriculumItem _word(String w, int tier) => CurriculumItem(
    id: _idFor(w), text: w, kind: ItemKind.word, tier: tier, prereqs: _charPrereqs(w));

CurriculumItem _phrase(String p, int tier) => CurriculumItem(
    id: _idFor(p), text: p, kind: ItemKind.phrase, tier: tier, prereqs: _charPrereqs(p));

/// The ordered curriculum. Kept as data so it can later move to an editable
/// asset. Characters are interleaved just ahead of the words/phrases that need
/// them, so the learner is always working on real material within a rep or two
/// of unlocking each new character.
final List<CurriculumItem> kCurriculum = _buildCurriculum();

List<CurriculumItem> _buildCurriculum() {
  final items = <CurriculumItem>[];
  final introducedChars = <String>{};
  final seenIds = <String>{};

  void addItem(CurriculumItem it) {
    if (seenIds.add(it.id)) items.add(it);
  }

  // Add the characters of [text] (that we haven't introduced yet) as their own
  // character items, in first-appearance order, then the word/phrase itself.
  // A single-character token IS just its character item — [make] is skipped so
  // we never create a word whose id collides with (and depends on) itself.
  void withChars(String text, int tier, CurriculumItem Function() make) {
    for (final ch in text.replaceAll(' ', '').split('')) {
      if (kMorseCode.containsKey(ch) && introducedChars.add(ch)) {
        addItem(_char(ch, tier));
      }
    }
    if (text.replaceAll(' ', '').length > 1) addItem(make());
  }

  // ---- Tier 1: the skeleton of a real contact ----
  // Highest-frequency on-air tokens. Each pulls in its characters just-in-time.
  const tier1Words = [
    'CQ', 'DE', 'K', 'R', 'TU', 'AR', 'SK', 'KN', 'BT', 'AS',
    '73', 'GM', 'GA', 'GE', 'OM', 'UR', 'HW', 'ES', 'TNX', 'FB',
  ];
  for (final w in tier1Words) {
    withChars(w, 1, () => _word(w, 1));
  }
  // Signal-report tokens (5NN = 599 in cut numbers, plus literal 599).
  for (final w in ['599', '5NN', 'RST']) {
    withChars(w, 1, () => _word(w, 1));
  }

  // ---- Tier 2: formulaic exchange phrases (copied as whole chunks) ----
  const tier2Phrases = [
    'CQ CQ CQ',
    'DE',
    'UR RST',
    'UR RST 599',
    'RST 599',
    'HW CPY',
    'HW CPY?',
    'NAME IS',
    'MY NAME IS',
    'QTH IS',
    'TNX FER CALL',
    'TNX FER QSO',
    'FB OM',
    'GM OM',
    '73 GL',
    'CU AGN',
    'RIG IS',
    'ANT IS',
    'WX IS',
    'HPE CU AGN',
  ];
  for (final p in tier2Phrases) {
    withChars(p, 2, () => _phrase(p, 2));
  }

  // ---- Tier 2.5: numbers in context (RST, serial, age, power) ----
  // Real contacts are full of numbers attached to meaning. Practising them in
  // context (not bare digits) is what you actually copy on the air.
  const numberChunks = [
    '5NN 14', '5NN 05', '5NN 22', 'RST 599', '599 OH', '599 CA',
    'AGE 44', 'AGE 33', 'PWR 5W', 'PWR 100W', 'NR 17', 'NR 03',
  ];
  for (final p in numberChunks) {
    withChars(p, 2, () => _phrase(p, 2));
  }

  // ---- Tier 3: common English high-frequency words ----
  // Fills out any remaining alphabet and builds general copy fluency.
  const tier3Words = [
    'THE', 'AND', 'YOU', 'FOR', 'ARE', 'WITH', 'THAT', 'HAVE', 'THIS', 'FROM',
    'THEY', 'WILL', 'WHAT', 'WHEN', 'YOUR', 'CAN', 'ALL', 'NOT', 'BUT', 'HAD',
    'WORD', 'GOOD', 'MAKE', 'TIME', 'VERY', 'JUST', 'KNOW', 'TAKE', 'YEAR', 'ZONE',
    'WAS', 'HIS', 'HER', 'SHE', 'HOW', 'WHY', 'WHO', 'OUT', 'NOW', 'NEW',
    'ONE', 'TWO', 'DAY', 'WAY', 'MAN', 'GET', 'SEE', 'USE', 'HIM', 'OLD',
    'THEIR', 'THERE', 'WHICH', 'WOULD', 'COULD', 'SHOULD', 'ABOUT', 'AFTER',
    'FIRST', 'OTHER', 'THINK', 'THING', 'WORLD', 'YEARS', 'GREAT', 'THESE',
    'BEEN', 'MORE', 'SOME', 'ONLY', 'OVER', 'ALSO', 'BACK', 'THAN', 'THEM',
    'WELL', 'WORK', 'LIKE', 'LONG', 'MANY', 'MUCH', 'MUST', 'NAME', 'HOME',
    'HERE', 'HAND', 'HIGH', 'KEEP', 'LAST', 'LIFE', 'PART', 'CALL', 'FIND',
    'GIVE', 'LOOK', 'MADE', 'MEAN', 'MOVE', 'NEED', 'OPEN', 'PLAY', 'SHOW',
    'TELL', 'TURN', 'WANT', 'WEEK', 'WENT', 'WORD', 'FEEL', 'FROM', 'GOES',
  ];
  for (final w in tier3Words) {
    withChars(w, 3, () => _word(w, 3));
  }

  // ---- Tier 4: callsign copy ----
  // Copying unfamiliar callsigns is the hardest, highest-value on-air skill.
  // A curated set of realistic calls (varied prefixes) plus portable (/P) forms
  // to introduce the '/' separator. By now all component chars are learned.
  const callsigns = [
    'W1ABC', 'K2LON', 'N3RAY', 'W4TOM', 'K5JIM', 'N6SAM', 'W7BOB', 'K8MAX',
    'N9LEE', 'W0PAT', 'VE3RM', 'DL4DX', 'G3XYZ', 'JA1QRS', 'VK2ANT',
    'W1ABC/P', 'K5JIM/P',
  ];
  for (final c in callsigns) {
    withChars(c, 4, () => _word(c, 4));
  }

  return items;
}

/// Fast lookup by id.
final Map<String, CurriculumItem> kCurriculumById = {
  for (final it in kCurriculum) it.id: it,
};
