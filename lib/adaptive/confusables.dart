/// Morse confusability: characters that are easy to mishear for one another.
///
/// Interleaving research shows the biggest gains come from practising *telling
/// confusable items apart* — so when the learner is missing a character, the
/// scheduler also resurfaces its confusable neighbours to build discrimination,
/// not just repetition of the missed item.
///
/// Confusability is derived from Morse structure: same length + adjacent by a
/// single dit/dah edit, prefix relationships, or reversals — the pairs
/// operators actually mix up (E/I/S/H run, U/V, B/D, etc.).
library;

/// Character → the characters most commonly confused with it. Symmetric.
const Map<String, List<String>> kConfusables = {
  // The dot run (length differs by one dit) — classic beginner confusion.
  'E': ['I', 'T'], // .  vs ..  / -
  'I': ['E', 'S', 'A'], // ..  vs .  / ...  / .-
  'S': ['I', 'H', 'U'], // ...  vs ..  / ....  / ..-
  'H': ['S', '5'], // ....  vs ...  / .....
  '5': ['H'], // .....  vs ....
  // The dash run.
  'T': ['M', 'E'], // -  vs --  / .
  'M': ['T', 'O'], // --  vs -  / ---
  'O': ['M', '0'], // ---  vs --  / -----
  '0': ['O', '9'], // -----  vs ---  / ----.
  // Single-edit / reversal pairs.
  'U': ['V', 'S', 'A'], // ..-  vs ...-  / ...  / .-
  'V': ['U', 'H', '4'], // ...-  vs ..-  / ....  / ....-
  'A': ['N', 'U', 'W', 'I'], // .-  vs -.  / ..-  / .--
  'N': ['A', 'D', 'M'], // -.  vs .-  / -..  / --
  'D': ['B', 'N', 'U'], // -..  vs -...  / -.  / ..-
  'B': ['D', '6'], // -...  vs -..  / -....
  'W': ['A', 'J', 'P'], // .--  vs .-  / .---  / .--.
  'G': ['Q', 'Z', 'W'], // --.  vs --.-  / --..  / .--
  'K': ['R', 'C', 'Y'], // -.-  vs .-.  / -.-.  / -.--
  'R': ['K', 'W', 'L'], // .-.  vs -.-  / .--  / .-..
  'F': ['L', 'P'], // ..-.  vs .-..  / .--.
  'L': ['R', 'F'], // .-..  vs .-.  / ..-.
  'P': ['W', 'F', 'X'], // .--.  vs .--  / ..-.  / -..-
  'X': ['P', 'K', 'Y'], // -..-  vs .--.  / -.-  / -.--
  'Y': ['K', 'X', 'C'], // -.--  vs -.-  / -..-  / -.-.
  'C': ['K', 'Y', 'Q'], // -.-.  vs -.-  / -.--  / --.-
  'Q': ['G', 'C', 'Z'], // --.-  vs --.  / -.-.  / --..
  'Z': ['G', 'Q', '7'], // --..  vs --.  / --.-  / --...
  'J': ['W', '1'], // .---  vs .--  / .----
  // Digit runs (adjacent numbers differ by one dit/dah).
  '1': ['2', 'J'],
  '2': ['1', '3'],
  '3': ['2', '4'],
  '4': ['3', '5', 'V'],
  '6': ['7', 'B'],
  '7': ['6', '8', 'Z'],
  '8': ['7', '9'],
  '9': ['8', '0'],
};

/// Characters commonly confused with [ch] (uppercase single char), or empty.
List<String> confusablesOf(String ch) => kConfusables[ch] ?? const [];

/// Characters we track per-character outcomes for (letters + digits). Excludes
/// punctuation, whose per-character stats aren't useful for confusable practice.
final Set<String> kConfusableScorable = {
  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
};
