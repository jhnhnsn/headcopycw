import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'morse_data.dart';

/// PARIS = 50 units; 1 WPM => 50 units per 60 s => 1 unit = 1.2/WPM seconds.
double unitSeconds(int wpm) => wpm > 0 ? 1.2 / wpm : 0.06;

enum EffectiveSpeedMode {
  /// Farnsworth: each character sent at actual speed, then padded to effective.
  farnsworth,

  /// Wordsworth: characters at actual; only inter‑word/inter‑group gaps extended.
  wordsworth,
}

/// Produces [(isTone, durationSec), ...] for [text] with optional Farnsworth/Wordsworth.
List<(bool, double)> textToMorseSegments({
  required String text,
  required int actualWpm,
  required int effectiveWpm,
  EffectiveSpeedMode effectiveMode = EffectiveSpeedMode.farnsworth,
  String? Function(String)? charLookup,
}) {
  final lookup = charLookup ?? ((c) => kMorseCode[c]);
  final unit = unitSeconds(actualWpm);
  final effUnit = effectiveWpm > 0 ? unitSeconds(effectiveWpm) : unit;
  final out = <(bool, double)>[];
  final words = text.toUpperCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  for (var w = 0; w < words.length; w++) {
    double wordCharUnits = 0;
    for (var c = 0; c < words[w].length; c++) {
      final pattern = lookup(words[w][c]);
      if (pattern == null) continue;
      double charUnits = 0;
      for (var i = 0; i < pattern.length; i++) {
        if (i > 0) {
          out.add((false, unit));
          charUnits += 1;
        }
        final dur = pattern[i] == '-' ? 3 * unit : unit;
        out.add((true, dur));
        charUnits += pattern[i] == '-' ? 3 : 1;
      }
      // Farnsworth: pad after each character to effective
      if (effectiveMode == EffectiveSpeedMode.farnsworth &&
          effectiveWpm > 0 &&
          effectiveWpm < actualWpm &&
          charUnits > 0) {
        final pad = charUnits * (effUnit - unit);
        if (pad > 0) out.add((false, pad));
      }
      if (c < words[w].length - 1) {
        out.add((false, 3 * unit));
      }
      wordCharUnits += charUnits;
    }
    // Inter‑word: 7 units at actual; Wordsworth extends to effective
    if (w < words.length - 1) {
      var gap = 7 * unit;
      if (effectiveMode == EffectiveSpeedMode.wordsworth &&
          effectiveWpm > 0 &&
          effectiveWpm < actualWpm) {
        gap = 7 * effUnit;
      }
      out.add((false, gap));
    }
  }
  return out;
}

/// Builds a WAV (44‑byte header + 16‑bit mono PCM) from segments and applies
/// a short end fade to avoid clicks.
Uint8List segmentsToWav(
  List<(bool, double)> segments, {
  required double frequencyHz,
  int sampleRate = 22050,
  double amplitude = 0.25,
}) {
  int totalSamples = 0;
  for (final s in segments) {
    totalSamples += (s.$2 * sampleRate).round();
  }
  int dataSize = totalSamples * 2;
  final buffer = ByteData(44 + dataSize);
  int offset = 0;

  // RIFF WAV header
  buffer.setUint8(offset++, 0x52);
  buffer.setUint8(offset++, 0x49);
  buffer.setUint8(offset++, 0x46);
  buffer.setUint8(offset++, 0x46);
  buffer.setUint32(offset, 36 + dataSize, Endian.little);
  offset += 4;
  buffer.setUint8(offset++, 0x57);
  buffer.setUint8(offset++, 0x41);
  buffer.setUint8(offset++, 0x56);
  buffer.setUint8(offset++, 0x45);
  buffer.setUint8(offset++, 0x66);
  buffer.setUint8(offset++, 0x6d);
  buffer.setUint8(offset++, 0x74);
  buffer.setUint8(offset++, 0x20);
  buffer.setUint32(offset, 16, Endian.little);
  offset += 4;
  buffer.setUint16(offset, 1, Endian.little);
  offset += 2;
  buffer.setUint16(offset, 1, Endian.little);
  offset += 2;
  buffer.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  buffer.setUint32(offset, sampleRate * 2, Endian.little);
  offset += 4;
  buffer.setUint16(offset, 2, Endian.little);
  offset += 2;
  buffer.setUint16(offset, 16, Endian.little);
  offset += 2;
  buffer.setUint8(offset++, 0x64);
  buffer.setUint8(offset++, 0x61);
  buffer.setUint8(offset++, 0x74);
  buffer.setUint8(offset++, 0x61);
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  final maxAmp = (32767 * amplitude).round();
  // Attack/release envelope duration in samples (~5ms) to avoid clicks
  final envelopeSamples = (0.005 * sampleRate).round();
  int globalSample = 0;
  for (final seg in segments) {
    final isTone = seg.$1;
    final dur = seg.$2;
    final n = (dur * sampleRate).round();
    for (var i = 0; i < n; i++) {
      int s;
      if (isTone) {
        // Apply envelope: fade in at start, fade out at end of each tone
        double envelope = 1.0;
        if (i < envelopeSamples) {
          // Attack (fade in)
          envelope = i / envelopeSamples;
        } else if (i >= n - envelopeSamples) {
          // Release (fade out)
          envelope = (n - 1 - i) / envelopeSamples;
        }
        final v = sin(2 * pi * frequencyHz * globalSample / sampleRate) * maxAmp * envelope;
        s = v.round().clamp(-32768, 32767);
      } else {
        s = 0;
      }
      buffer.setInt16(offset, s, Endian.little);
      offset += 2;
      globalSample++;
    }
  }

  // Fade out last ~2 ms to avoid click
  final fadeSamples = (0.002 * sampleRate).round().clamp(1, totalSamples);
  for (var i = 0; i < fadeSamples; i++) {
    final idx = totalSamples - 1 - i;
    final byteOffset = 44 + idx * 2;
    final s = buffer.getInt16(byteOffset, Endian.little);
    final gain = fadeSamples <= 1 ? 0.0 : i / (fadeSamples - 1);
    buffer.setInt16(byteOffset, (s * gain).round().clamp(-32768, 32767), Endian.little);
  }

  return buffer.buffer.asUint8List();
}

/// One-shot: generate and play [text] in Morse. Uses [actualWpm], [effectiveWpm],
/// [effectiveMode], [frequencyHz]. [player] is used for playback; call [onComplete] when done.
Future<void> playMorseText({
  required AudioPlayer player,
  required String text,
  required int actualWpm,
  required int effectiveWpm,
  required double frequencyHz,
  EffectiveSpeedMode effectiveMode = EffectiveSpeedMode.farnsworth,
  void Function()? onComplete,
}) async {
  await player.stop();
  final segments = textToMorseSegments(
    text: text,
    actualWpm: actualWpm,
    effectiveWpm: effectiveWpm,
    effectiveMode: effectiveMode,
  );
  final wav = segmentsToWav(segments, frequencyHz: frequencyHz);
  await player.play(BytesSource(wav));
  if (onComplete != null) {
    player.onPlayerComplete.listen((_) {
      onComplete();
    });
  }
}
