import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'morse_player.dart';

MorsePlayer createMorsePlayer() => _IoMorsePlayer();

/// A temp file (not BytesSource) is required because BytesSource fails on
/// iOS/macOS with AVPlayer.
class _IoMorsePlayer implements MorsePlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List wav, {String name = 'cw_tone'}) async {
    final tempDir = await getTemporaryDirectory();
    final wavFile = File('${tempDir.path}/$name.wav');
    await wavFile.writeAsBytes(wav, flush: true);
    await _player.stop();
    await _player.play(DeviceFileSource(wavFile.path));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  void dispose() => _player.dispose();
}
