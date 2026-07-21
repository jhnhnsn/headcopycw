import 'package:flutter_test/flutter_test.dart';
import 'package:head_copy_cw_trainer/morse_data.dart';
import 'package:head_copy_cw_trainer/adaptive/generator.dart';

void main() {
  final callRe = RegExp(r'^[A-Z]{1,2}[0-9][A-Z]{1,3}(/P)?$');

  test('callsigns match a valid shape and encode in Morse', () {
    final gen = CopyGenerator(seed: 7);
    for (var i = 0; i < 200; i++) {
      final call = gen.callsign();
      expect(callRe.hasMatch(call), isTrue, reason: 'bad call: $call');
      for (final ch in call.replaceAll('/', '').split('')) {
        expect(kMorseCode.containsKey(ch), isTrue,
            reason: 'unencodable "$ch" in $call');
      }
    }
  });

  test('all generated item text encodes in Morse', () {
    final gen = CopyGenerator(seed: 3, myCallsign: 'K9ABC');
    for (var i = 0; i < 300; i++) {
      final item = gen.next();
      for (final ch in item.text.replaceAll(' ', '').replaceAll('/', '').split('')) {
        // '?' is in kMorseCode; every other char must be too.
        expect(kMorseCode.containsKey(ch), isTrue,
            reason: 'unencodable "$ch" in "${item.text}"');
      }
      expect(isGeneratedId(item.id), isTrue);
    }
  });

  test('exchanges use the user callsign when set', () {
    final gen = CopyGenerator(seed: 5, myCallsign: 'K9XYZ');
    var sawMine = false;
    for (var i = 0; i < 100; i++) {
      if (gen.exchange().contains('K9XYZ')) sawMine = true;
    }
    expect(sawMine, isTrue);
  });

  test('exchanges fall back to a placeholder call when none set', () {
    final gen = CopyGenerator(seed: 5); // no callsign
    // Should never crash and never contain an empty "DE  " gap.
    for (var i = 0; i < 100; i++) {
      final ex = gen.exchange();
      expect(ex.contains('DE  '), isFalse, reason: 'empty call in "$ex"');
    }
  });

  test('same seed → identical sequence (deterministic)', () {
    final a = CopyGenerator(seed: 42, myCallsign: 'W1AW');
    final b = CopyGenerator(seed: 42, myCallsign: 'W1AW');
    for (var i = 0; i < 50; i++) {
      expect(a.next().text, b.next().text);
    }
  });

  test('different seeds → different sequences', () {
    final a = CopyGenerator(seed: 1);
    final b = CopyGenerator(seed: 2);
    final seqA = [for (var i = 0; i < 20; i++) a.next().text];
    final seqB = [for (var i = 0; i < 20; i++) b.next().text];
    expect(seqA, isNot(equals(seqB)));
  });
}
