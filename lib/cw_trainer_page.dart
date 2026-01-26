import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'morse_data.dart';
import 'morse_engine.dart';
import 'tone_demo_page.dart';

enum PracticeMode { characters, words, groups, qso }

const _kValidTones = [400, 500, 600, 700, 800, 900];

class CwTrainerSettings {
  int actualWpm = 20;
  int effectiveWpm = 15;
  EffectiveSpeedMode effectiveMode = EffectiveSpeedMode.farnsworth;
  int kochLearnedCount = 10;
  int frequencyHz = 600;
  int groupSize = 5;
  bool wordsOnlyLearnedLetters = true;
  /// Delay (ms) before showing received characters; playing the next is not delayed.
  int displayDelayMs = 400;

  static Future<CwTrainerSettings> load(SharedPreferences prefs) async {
    final hz = prefs.getInt('frequencyHz') ?? 600;
    return CwTrainerSettings()
      ..actualWpm = prefs.getInt('actualWpm') ?? 20
      ..effectiveWpm = prefs.getInt('effectiveWpm') ?? 15
      ..effectiveMode = prefs.getString('effectiveMode') == 'wordsworth' ? EffectiveSpeedMode.wordsworth : EffectiveSpeedMode.farnsworth
      ..kochLearnedCount = prefs.getInt('kochLearnedCount') ?? 10
      ..frequencyHz = _kValidTones.contains(hz) ? hz : 600
      ..groupSize = prefs.getInt('groupSize') ?? 5
      ..wordsOnlyLearnedLetters = prefs.getBool('wordsOnlyLearnedLetters') ?? true
      ..displayDelayMs = prefs.getInt('displayDelayMs') ?? 400;
  }

  static Future<void> save(SharedPreferences prefs, CwTrainerSettings s) async {
    await prefs.setInt('actualWpm', s.actualWpm);
    await prefs.setInt('effectiveWpm', s.effectiveWpm);
    await prefs.setString('effectiveMode', s.effectiveMode == EffectiveSpeedMode.wordsworth ? 'wordsworth' : 'farnsworth');
    await prefs.setInt('kochLearnedCount', s.kochLearnedCount);
    await prefs.setInt('frequencyHz', s.frequencyHz);
    await prefs.setInt('groupSize', s.groupSize);
    await prefs.setBool('wordsOnlyLearnedLetters', s.wordsOnlyLearnedLetters);
    await prefs.setInt('displayDelayMs', s.displayDelayMs);
  }
}

class CwTrainerPage extends StatefulWidget {
  const CwTrainerPage({super.key});

  @override
  State<CwTrainerPage> createState() => _CwTrainerPageState();
}

class _CwTrainerPageState extends State<CwTrainerPage> {
  final AudioPlayer _player = AudioPlayer();
  final Random _rnd = Random();
  final ScrollController _scrollController = ScrollController();
  CwTrainerSettings _settings = CwTrainerSettings();
  PracticeMode _mode = PracticeMode.characters;
  bool _running = false;
  String _displayText = '';
  StreamSubscription? _completeSub;
  int _qsoNext = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final s = await CwTrainerSettings.load(prefs);
    if (mounted) setState(() => _settings = s);
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _scrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  Set<String> get _learned => kochLearnedSet(_settings.kochLearnedCount).toSet();

  List<String> get _filteredWords {
    final allowed = _learned;
    if (_settings.wordsOnlyLearnedLetters) {
      return kWords.where((w) => wordUsesOnly(w, allowed)).toList();
    }
    return kWords.where((w) => w.toUpperCase().split('').every((c) => kMorseCode.containsKey(c))).toList();
  }

  String _nextCharacters() {
    final set = _learned;
    if (set.isEmpty) return '';
    return set.elementAt(_rnd.nextInt(set.length));
  }

  String _nextGroup() {
    final set = _learned;
    if (set.isEmpty) return '';
    final n = _settings.groupSize.clamp(1, set.length);
    final list = set.toList()..shuffle(_rnd);
    return list.take(n).join();
  }

  String _nextWord() {
    final list = _filteredWords;
    if (list.isEmpty) return _nextCharacters();
    return list[_rnd.nextInt(list.length)];
  }

  String _nextQso() {
    if (kQsoPhrases.isEmpty) return '';
    final s = kQsoPhrases[_qsoNext % kQsoPhrases.length];
    _qsoNext++;
    return s;
  }

  String _nextPayload() {
    switch (_mode) {
      case PracticeMode.characters:
        return _nextCharacters();
      case PracticeMode.words:
        return _nextWord();
      case PracticeMode.groups:
        return _nextGroup();
      case PracticeMode.qso:
        return _nextQso();
    }
  }

  Future<void> _playNext() async {
    if (!_running) return;
    final text = _nextPayload();
    if (text.isEmpty) {
      _scheduleNext();
      return;
    }
    final segments = textToMorseSegments(
      text: text,
      actualWpm: _settings.actualWpm,
      effectiveWpm: _settings.effectiveWpm,
      effectiveMode: _settings.effectiveMode,
    );
    final wav = segmentsToWav(segments, frequencyHz: _settings.frequencyHz.toDouble());
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!_running) return;
      final sep = (_mode == PracticeMode.characters || _mode == PracticeMode.words) ? ' ' : '\n';
      // Delay only the display of what was just played.
      Future.delayed(Duration(milliseconds: _settings.displayDelayMs), () {
        if (!mounted) return;
        setState(() {
          _displayText = _displayText.isEmpty ? text : '$_displayText$sep$text';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      });
      // Play next immediately (no delay).
      _scheduleNext();
    });
    await _player.stop();
    await _player.play(BytesSource(wav));
  }

  void _scheduleNext() {
    if (!_running) return;
    Future.delayed(Duration.zero, _playNext);
  }

  Future<void> _toggleRun() async {
    if (_running) {
      setState(() => _running = false);
      await _player.stop();
      _completeSub?.cancel();
      return;
    }
    setState(() {
      _running = true;
      _displayText = '';
    });
    _playNext();
  }

  Future<void> _openSetup() async {
    final s = await Navigator.of(context).push<CwTrainerSettings>(
      MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings)),
    );
    if (s != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await CwTrainerSettings.save(prefs, s);
      setState(() => _settings = s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CW Trainer (Koch)'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSetup),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'tone') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ToneDemoPage()));
            },
            itemBuilder: (ctx) => [const PopupMenuItem(value: 'tone', child: Text('Tone & Hello World'))],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Effective speed indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Effective: ${_settings.effectiveWpm} WPM  ·  Actual: ${_settings.actualWpm} WPM  ·  ${_settings.effectiveMode == EffectiveSpeedMode.farnsworth ? "Farnsworth" : "Wordsworth"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Mode
            SegmentedButton<PracticeMode>(
              segments: [
                ButtonSegment(value: PracticeMode.characters, label: Text('Chars', maxLines: 1, overflow: TextOverflow.ellipsis), icon: const Icon(Icons.text_fields)),
                ButtonSegment(value: PracticeMode.groups, label: Text('Groups', maxLines: 1, overflow: TextOverflow.ellipsis), icon: const Icon(Icons.grid_on)),
                ButtonSegment(value: PracticeMode.words, label: Text('Words', maxLines: 1, overflow: TextOverflow.ellipsis), icon: const Icon(Icons.article)),
                ButtonSegment(value: PracticeMode.qso, label: Text('QSO', maxLines: 1, overflow: TextOverflow.ellipsis), icon: const Icon(Icons.record_voice_over)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 16),
            // Display (echo after sent)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    _displayText.isEmpty ? '—' : _displayText,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Start / Stop
            FilledButton.icon(
              onPressed: _toggleRun,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'Stop' : 'Start'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final CwTrainerSettings settings;

  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _actualWpm;
  late int _effectiveWpm;
  late EffectiveSpeedMode _effectiveMode;
  late int _kochCount;
  late double _pitchSlider;
  late int _groupSize;
  late bool _wordsOnlyLearned;
  late int _displayDelayMs;

  @override
  void initState() {
    super.initState();
    _actualWpm = widget.settings.actualWpm;
    _effectiveWpm = widget.settings.effectiveWpm;
    _effectiveMode = widget.settings.effectiveMode;
    _kochCount = widget.settings.kochLearnedCount;
    _pitchSlider = _kValidTones.indexOf(widget.settings.frequencyHz).clamp(0, _kValidTones.length - 1).toDouble();
    _groupSize = widget.settings.groupSize;
    _wordsOnlyLearned = widget.settings.wordsOnlyLearnedLetters;
    _displayDelayMs = widget.settings.displayDelayMs;
  }

  void _save() {
    Navigator.of(context).pop(CwTrainerSettings()
      ..actualWpm = _actualWpm
      ..effectiveWpm = _effectiveWpm
      ..effectiveMode = _effectiveMode
      ..kochLearnedCount = _kochCount
      ..frequencyHz = _kValidTones[_pitchSlider.round().clamp(0, _kValidTones.length - 1)]
      ..groupSize = _groupSize
      ..wordsOnlyLearnedLetters = _wordsOnlyLearned
      ..displayDelayMs = _displayDelayMs);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Setup'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _save),
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Actual speed (WPM)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _actualWpm.toDouble(), min: 5, max: 40, divisions: 35, label: '$_actualWpm', onChanged: (v) => setState(() => _actualWpm = v.round())),
            Text('Effective speed (WPM)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _effectiveWpm.toDouble(), min: 5, max: 40, divisions: 35, label: '$_effectiveWpm', onChanged: (v) => setState(() => _effectiveWpm = v.round())),
            Text('Effective speed mode', style: Theme.of(context).textTheme.labelLarge),
            SegmentedButton<EffectiveSpeedMode>(
              segments: [
                ButtonSegment(value: EffectiveSpeedMode.farnsworth, label: Text('Farnsworth', maxLines: 1, overflow: TextOverflow.ellipsis)),
                ButtonSegment(value: EffectiveSpeedMode.wordsworth, label: Text('Wordsworth', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              selected: {_effectiveMode},
              onSelectionChanged: (s) => setState(() => _effectiveMode = s.first),
            ),
            const SizedBox(height: 8),
            Text('Characters learned (Koch, 2–40)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _kochCount.toDouble(), min: 2, max: 40, divisions: 38, label: '$_kochCount', onChanged: (v) => setState(() => _kochCount = v.round())),
            Text('CW pitch (Hz)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _pitchSlider, min: 0, max: (_kValidTones.length - 1).toDouble(), divisions: _kValidTones.length - 1, label: '${_kValidTones[_pitchSlider.round()]}', onChanged: (v) => setState(() => _pitchSlider = v)),
            Text('Group size (for Groups mode)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _groupSize.toDouble(), min: 2, max: 10, divisions: 8, label: '$_groupSize', onChanged: (v) => setState(() => _groupSize = v.round())),
            CheckboxListTile(
              title: const Text('Words: only learnt letters'),
              value: _wordsOnlyLearned,
              onChanged: (v) => setState(() => _wordsOnlyLearned = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Text('Display delay (ms) – when to show received text', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _displayDelayMs.toDouble(), min: 0, max: 5000, divisions: 50, label: '$_displayDelayMs', onChanged: (v) => setState(() => _displayDelayMs = v.round())),
          ],
        ),
      ),
      ),
    );
  }
}
