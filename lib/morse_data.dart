/// Morse code data: full character set, Koch learning order, and word lists
/// for the CW Trainer (G4FON-style: https://www.g4fon.net/CW%20Trainer2.php).

/// Full ITU/RFC 3629 Morse (letters, digits, . , / ?).
const Map<String, String> kMorseCode = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.', 'F': '..-.',
  'G': '--.', 'H': '....', 'I': '..', 'J': '.---', 'K': '-.-', 'L': '.-..',
  'M': '--', 'N': '-.', 'O': '---', 'P': '.--.', 'Q': '--.-', 'R': '.-.',
  'S': '...', 'T': '-', 'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-',
  'Y': '-.--', 'Z': '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
  '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
  '.': '.-.-.-', ',': '--..--', '/': '-..-.', '?': '..--..',
};

/// Koch method: order in which characters are learned (40 built‑in).
/// Aligned with common CW trainers (G4FON-style, CWOps‑compatible option exists).
const List<String> kKochOrder = [
  'K', 'M', 'R', 'S', 'U', 'A', 'P', 'T', 'L', 'O', 'W', 'I', '.', 'N', 'J',
  'E', 'F', '0', 'Y', ',', 'V', 'G', '5', '/', 'Q', '9', 'Z', 'H', '3', '8',
  'B', '?', '4', '2', '7', 'C', '1', '6', 'X',
];

/// Built‑in words for practice. Uppercase; filtered by learned set.
const List<String> kWords = [
  'A', 'I', 'SO', 'US', 'AS', 'AT', 'AM', 'SAT', 'AIM', 'ARM', 'ART', 'ITS',
  'OUT', 'PAT', 'RAT', 'SIT', 'TO', 'TOO', 'UP', 'ALL', 'ARE', 'BUT', 'FOR',
  'HAD', 'HAS', 'HER', 'HIM', 'HIS', 'NOT', 'NOW', 'OLD', 'OUR', 'SAY', 'SEE',
  'SHE', 'THE', 'TWO', 'WAY', 'WHO', 'AND', 'CAN', 'DAY', 'GET', 'HOW', 'MAN',
  'NEW', 'ONE', 'YOU', 'DE', 'CQ', 'K', 'R', 'SK', 'AR', 'BT', 'KN', 'VE',
  'AA', 'AN', 'BE', 'DO', 'GO', 'HE', 'IF', 'IS', 'IT', 'ME', 'MY', 'NO', 'OF',
  'ON', 'OR', 'SO', 'WE', 'BEST', 'CALL', 'FROM', 'GAME', 'GAVE', 'HERE',
  'HOME', 'MORE', 'MOST', 'NAME', 'SOME', 'TAKE', 'THAN', 'THAT', 'THEM',
  'THEN', 'THEY', 'THIS', 'WHAT', 'WHEN', 'WILL', 'WITH', 'YOUR', 'AGAIN',
  'ABOUT', 'AFTER', 'BEFORE', 'BEING', 'CAME', 'COME', 'COULD', 'EACH',
  'FIRST', 'FOUND', 'GIVE', 'GOOD', 'GREAT', 'HAS', 'HAVE', 'JUST', 'LONG',
  'MAKE', 'MANY', 'MUCH', 'MUST', 'ONLY', 'OTHER', 'OVER', 'SHOULD', 'STILL',
  'SUCH', 'THEIR', 'THERE', 'THESE', 'THOSE', 'THREE', 'UNDER', 'VERY',
  'WERE', 'WHERE', 'WHICH', 'WHILE', 'WOULD', 'YOUR',
];

/// Canned QSO snippets (sent one after another in QSO mode).
const List<String> kQsoPhrases = [
  'CQ CQ CQ DE G4FON G4FON K',
  'G4FON DE W1AW GM TNX CALL BT NAME IS BILL BT QTH BOSTON BT HW? G4FON DE W1AW K',
  'W1AW DE G4FON GM BILL TNX BT NAME IS JOHN BT QTH LONDON BT HW CPI? W1AW DE G4FON K',
  'G4FON DE W1AW TNX JOHN BT 5NN BT QSL UR 599 MY 599 BT CU AGN G4FON DE W1AW SK',
];

/// Returns the first [count] characters in Koch order (learned set).
List<String> kochLearnedSet(int count) {
  return kKochOrder.take(count.clamp(0, kKochOrder.length)).toList();
}

/// True if [word] uses only characters in [allowed].
bool wordUsesOnly(String word, Set<String> allowed) {
  for (var i = 0; i < word.length; i++) {
    if (!allowed.contains(word[i].toUpperCase())) return false;
  }
  return true;
}
