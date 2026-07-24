import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:head_copy_cw_trainer/cw_trainer_page.dart';

void main() {
  test('CwTrainerSettings round-trips the Copy-only fields', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final s = CwTrainerSettings()
      ..frequencyHz = 800
      ..sessionLengthMinutes = 7
      ..callsign = 'W1ABC';
    await CwTrainerSettings.save(prefs, s);

    final loaded = await CwTrainerSettings.load(prefs);
    expect(loaded.frequencyHz, 800);
    expect(loaded.sessionLengthMinutes, 7);
    expect(loaded.callsign, 'W1ABC');
  });

  test('defaults are sensible when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final loaded = await CwTrainerSettings.load(prefs);
    expect(loaded.callsign, '');
    expect(loaded.sessionLengthMinutes, 5);
  });

  test('normalizeCallsign keeps only encodable chars, uppercased', () {
    expect(normalizeCallsign('w1abc'), 'W1ABC');
    expect(normalizeCallsign('ve3rm/p'), 'VE3RM/P');
    expect(normalizeCallsign('a!b@c'), 'ABC');
  });
}
