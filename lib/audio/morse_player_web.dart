import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'morse_player.dart';

MorsePlayer createMorsePlayer() => _WebMorsePlayer();

/// Web Audio playback. One AudioContext is unlocked on the first tap/keypress,
/// after which the Copy loop can start items from timers without tripping
/// browser autoplay blocking (which HTML audio elements do, notably on iOS).
class _WebMorsePlayer implements MorsePlayer {
  final _complete = StreamController<void>.broadcast();
  web.AudioBufferSourceNode? _node;

  _WebMorsePlayer() {
    _AudioUnlock.install();
  }

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> play(Uint8List wav, {String name = 'cw_tone'}) async {
    await stop();
    final ctx = _AudioUnlock.context;
    if (ctx.state != 'running') await ctx.resume().toDart;

    final sampleRate = ByteData.sublistView(wav).getUint32(24, Endian.little);
    final pcm = Int16List.sublistView(wav, 44);
    final samples = Float32List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      samples[i] = pcm[i] / 32768;
    }
    final buffer = ctx.createBuffer(1, samples.length, sampleRate.toDouble());
    buffer.copyToChannel(samples.toJS, 0);

    final node = ctx.createBufferSource()
      ..buffer = buffer
      ..connect(ctx.destination);
    node.onended = (web.Event _) {
      // A node replaced or stopped by stop() must not report completion.
      if (identical(_node, node)) {
        _node = null;
        _complete.add(null);
      }
    }.toJS;
    _node = node;
    node.start();
  }

  @override
  Future<void> stop() async {
    final node = _node;
    _node = null;
    node?.stop();
  }

  @override
  void dispose() {
    stop();
    _complete.close();
  }
}

/// Shared AudioContext, resumed from inside the first user gesture so later
/// timer-driven playback is allowed.
class _AudioUnlock {
  static web.AudioContext? _ctx;
  static bool _installed = false;

  static web.AudioContext get context => _ctx ??= web.AudioContext();

  static void install() {
    if (_installed) return;
    _installed = true;
    late final JSFunction listener;
    listener = (web.Event _) {
      final ctx = context;
      ctx.resume();
      // iOS only unlocks once something has actually been started in-gesture.
      final silent = ctx.createBufferSource()
        ..buffer = ctx.createBuffer(1, 1, 22050)
        ..connect(ctx.destination);
      silent.start();
      for (final type in const ['pointerdown', 'keydown', 'touchend']) {
        web.window.removeEventListener(type, listener, true.toJS);
      }
    }.toJS;
    for (final type in const ['pointerdown', 'keydown', 'touchend']) {
      web.window.addEventListener(type, listener, true.toJS);
    }
  }
}
