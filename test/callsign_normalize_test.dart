import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/cw_trainer_page.dart';

void main() {
  test('normalizeCallsign uppercases, trims, and keeps encodable chars', () {
    expect(normalizeCallsign('w1abc'), 'W1ABC');
    expect(normalizeCallsign('  k9xyz  '), 'K9XYZ');
    expect(normalizeCallsign('VE3RM/P'), 'VE3RM/P'); // '/' is encodable
  });

  test('strips characters the Morse engine cannot send', () {
    // '@', '!', spaces inside are dropped (not in kMorseCode).
    expect(normalizeCallsign('w1@abc!'), 'W1ABC');
    expect(normalizeCallsign('---'), ''); // '-' is not a table key
  });

  test('empty / whitespace input → empty string', () {
    expect(normalizeCallsign(''), '');
    expect(normalizeCallsign('   '), '');
  });
}
