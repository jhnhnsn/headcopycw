/// Plays rendered Morse WAVs. Split by platform because the native path
/// (audioplayers + a temp file) has no filesystem on web, and HTML audio
/// elements on web get blocked by autoplay rules when the Copy loop starts the
/// next item from a timer rather than a tap.
library;

import 'dart:typed_data';

import 'morse_player_io.dart' if (dart.library.js_interop) 'morse_player_web.dart';

abstract class MorsePlayer {
  factory MorsePlayer() => createMorsePlayer();

  /// Fires each time playback reaches its natural end (not on [stop]).
  Stream<void> get onComplete;

  /// Stops anything playing, then plays [wav] (44-byte header + 16-bit mono
  /// PCM, as produced by segmentsToWav). [name] distinguishes concurrent
  /// renders on platforms that stage audio through a file.
  Future<void> play(Uint8List wav, {String name = 'cw_tone'});

  Future<void> stop();

  void dispose();
}
