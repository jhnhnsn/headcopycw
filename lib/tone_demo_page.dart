import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'morse_engine.dart';

/// Simple pitch slider, play tone, and Play Hello World in Morse (from the original app).
class ToneDemoPage extends StatefulWidget {
  const ToneDemoPage({super.key});

  @override
  State<ToneDemoPage> createState() => _ToneDemoPageState();
}

class _ToneDemoPageState extends State<ToneDemoPage> {
  final AudioPlayer _player = AudioPlayer();
  double _pitchSlider = 2; // 600 Hz
  static const _tones = [400, 500, 600, 700, 800, 900];

  int get _frequencyHz => _tones[_pitchSlider.round().clamp(0, _tones.length - 1)];

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playTone() async {
    await _player.stop();
    final wav = segmentsToWav(
      [(true, 0.5)],
      frequencyHz: _frequencyHz.toDouble(),
    );
    await _player.play(BytesSource(wav));
  }

  Future<void> _playHelloWorld() async {
    await _player.stop();
    final seg = textToMorseSegments(text: 'HELLO WORLD', actualWpm: 20, effectiveWpm: 20);
    final wav = segmentsToWav(seg, frequencyHz: _frequencyHz.toDouble());
    await _player.play(BytesSource(wav));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tone & Hello World')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$_frequencyHz Hz', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Slider(value: _pitchSlider, min: 0, max: (_tones.length - 1).toDouble(), divisions: _tones.length - 1, label: '$_frequencyHz Hz', onChanged: (v) => setState(() => _pitchSlider = v)),
              Text('CW sidetone (${_tones.first}–${_tones.last} Hz)', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _playTone, child: const Text('Play tone')),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _playHelloWorld, child: const Text('Play Hello World in Morse')),
            ],
          ),
        ),
      ),
    );
  }
}
