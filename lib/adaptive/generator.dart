/// Endless-practice generator for the adaptive "Copy" mode.
///
/// Once the fixed [kCurriculum] is exhausted, this produces an unbounded stream
/// of realistic on-air material — random valid callsigns and short exchanges —
/// so the learner keeps drilling the *rhythm* of unfamiliar calls and real QSO
/// flow rather than running out of things to copy.
///
/// Pure and deterministic: seeded via the constructor and advanced by an
/// internal counter (no `Random()`/`DateTime.now()`), so tests are reproducible
/// and the class carries no Flutter/IO dependency.
library;

import 'curriculum.dart';

/// Synthetic id prefix so generated items are distinguishable from curriculum
/// ids and can be excluded from progress counts / persistence.
const String kGeneratedIdPrefix = 'GEN:';

/// True if [id] refers to a generated (ephemeral) item.
bool isGeneratedId(String id) => id.startsWith(kGeneratedIdPrefix);

/// Deterministic pseudo-random source. A tiny LCG is enough here — we only need
/// varied, repeatable sequences, not statistical quality.
class _Lcg {
  int _state;
  _Lcg(int seed) : _state = (seed ^ 0x9E3779B9) & 0x7FFFFFFF;

  int nextInt(int max) {
    // Numerical Recipes LCG constants.
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return max <= 0 ? 0 : _state % max;
  }

  bool chance(int percent) => nextInt(100) < percent;

  T pick<T>(List<T> options) => options[nextInt(options.length)];
}

/// Generates realistic amateur callsigns and short QSO exchanges.
class CopyGenerator {
  final _Lcg _rng;

  /// The learner's own callsign, used as the "me" side of exchanges. Empty
  /// falls back to a neutral placeholder.
  final String myCallsign;

  CopyGenerator({int seed = 1, this.myCallsign = ''}) : _rng = _Lcg(seed);

  // Common single-letter and multi-letter prefixes (US + a few DX), chosen to
  // exercise varied rhythms. All letters are in the Morse table.
  static const _prefixes = [
    'W', 'K', 'N', 'AA', 'AB', 'KA', 'KB', 'WA', 'WB', 'NA', // US-style
    'VE', 'G', 'DL', 'F', 'EA', 'JA', 'VK', 'ZL', 'PY', 'OH', // DX
  ];

  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static const _states = [
    'OH', 'CA', 'TX', 'NY', 'FL', 'PA', 'IL', 'MI', 'GA', 'NC',
    'WA', 'CO', 'AZ', 'MA', 'VA', 'OR', 'TN', 'MO', 'MN', 'WI',
  ];

  /// Produces one random callsign string (e.g. "K7XQ", "DL4DX", "W1ABC/P").
  String callsign() {
    final prefix = _rng.pick(_prefixes);
    final digit = _rng.nextInt(10).toString();
    final suffixLen = 1 + _rng.nextInt(3); // 1..3 letters
    final sb = StringBuffer(prefix)..write(digit);
    for (var i = 0; i < suffixLen; i++) {
      sb.write(_letters[_rng.nextInt(_letters.length)]);
    }
    var call = sb.toString();
    if (_rng.chance(12)) call = '$call/P'; // occasional portable
    return call;
  }

  String get _me => myCallsign.isNotEmpty ? myCallsign : 'W1ABC';

  /// Produces one random short exchange string combining calls + learned chunks.
  String exchange() {
    final other = callsign();
    switch (_rng.nextInt(6)) {
      case 0:
        return '$other DE $_me K';
      case 1:
        return '$other DE $_me 5NN K';
      case 2:
        return 'UR RST 599 QTH ${_rng.pick(_states)}';
      case 3:
        return '$other DE $_me TNX 73';
      case 4:
        return '$other DE $_me GM OM';
      default:
        return 'CQ CQ DE $_me K';
    }
  }

  /// The next generated practice item. ~40% bare callsigns (the hardest, most
  /// valuable copy), ~60% short exchanges. Ids are stable to the text so a
  /// repeat of the same string reuses one SRS slot within a session.
  CurriculumItem next() {
    final asCall = _rng.chance(40);
    final text = asCall ? callsign() : exchange();
    return CurriculumItem(
      id: '$kGeneratedIdPrefix$text',
      text: text,
      kind: asCall ? ItemKind.word : ItemKind.phrase,
      tier: 99,
      prereqs: const [],
    );
  }
}
