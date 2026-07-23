import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../morse_engine.dart';
import 'curriculum.dart';
import 'curriculum_provider.dart';
import 'cw_keyboard.dart';
import 'generator.dart';
import 'progress_page.dart';
import 'progress_stats.dart';
import 'progress_store.dart';
import 'srs.dart';

/// Minimal read-only view of the trainer settings the adaptive loop needs.
/// Mirrors fields on CwTrainerSettings so we avoid a circular import. Copy sets
/// its own speed (fixed char speed + adaptive effective WPM), so no WPM fields.
class AdaptiveSettings {
  final int frequencyHz;

  /// Session length in minutes (0 = unlimited).
  final int sessionLengthMinutes;

  /// The learner's own callsign (uppercase, encodable), or '' if unset.
  final String callsign;

  /// When true, run "copy on paper": no typing during the session (hear →
  /// write → Done), then score everything at the end.
  final bool paperMode;

  const AdaptiveSettings({
    required this.frequencyHz,
    required this.sessionLengthMinutes,
    this.callsign = '',
    this.paperMode = false,
  });
}

/// Lifecycle phases of one presentation.
enum _Phase {
  idle,
  playing,
  buffering,
  awaitingInput, // typed mode: CW keyboard is up
  paperCopy, // paper mode: write on paper, then tap Done
  paperScoring, // paper mode: enter what you wrote to score at session end
  revealed,
}

/// The adaptive "Copy" mode. Plays a curriculum item, waits a buffer beat, lets
/// the learner type what they heard, scores accuracy + latency, reveals, and
/// schedules the next item via the SRS scheduler. All copy is head-copy: the
/// answer is hidden until the learner commits.
class AdaptivePage extends StatefulWidget {
  final AdaptiveSettings settings;

  /// Directory for the progress JSON. Null on web → in-memory only.
  final Directory? storageDir;

  /// Clock injection for testability; defaults to [DateTime.now].
  final DateTime Function() now;

  // ignore: prefer_const_constructors_in_immutables
  AdaptivePage({
    super.key,
    required this.settings,
    required this.storageDir,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  State<AdaptivePage> createState() => AdaptivePageState();
}

class AdaptivePageState extends State<AdaptivePage> {
  /// Set true by an external progress-reset so the *outgoing* page instance
  /// (which still holds in-memory SRS state) does not re-flush and resurrect the
  /// just-deleted progress file when it disposes.
  static bool suppressNextDisposeFlush = false;

  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _answerFocus = FocusNode();

  late SrsScheduler _scheduler;
  ProgressStore? _store;
  AdaptiveProgress _progress = AdaptiveProgress();

  /// Curriculum composed with the learner's callsign (if any), plus its lookup.
  late final List<CurriculumItem> _curriculum;
  late final Map<String, CurriculumItem> _curriculumById;

  /// Endless-practice generator, used once the fixed curriculum is exhausted.
  late final CopyGenerator _generator;

  _Phase _phase = _Phase.idle;
  bool _running = false;

  CurriculumItem? _current;
  StreamSubscription? _completeSub;
  Timer? _bufferTimer;
  Timer? _sessionTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  /// "Too long to answer" bar: ticks while awaiting input, drains toward a
  /// target that scales with item length. Visual only — never auto-submits.
  Timer? _elapsedTimer;
  final Stopwatch _elapsedWatch = Stopwatch();
  int _elapsedTargetMs = 3000;

  /// Stopwatch started when the input field appears. Recognition latency is
  /// captured at the FIRST keystroke — that is the instant the learner
  /// recognised the sound. Time spent typing the rest of the answer and
  /// reaching for Enter is deliberately excluded (it is motor, not perception).
  final Stopwatch _latencyWatch = Stopwatch();

  /// Latency to the first keystroke this presentation, or null before typing.
  int? _recognitionLatencyMs;
  int? _lastLatencyMs;
  bool? _lastCorrect;

  // Session tallies for the end-of-session summary.
  int _sessionSeen = 0;
  int _sessionCorrect = 0;
  final List<int> _sessionLatencies = [];
  final List<String> _sessionUnlockedIds = [];
  DateTime? _sessionStart;

  /// Items this session presented WITH a copy-behind buffer active, and how many
  /// were correct — the retention-specific signal that adapts the buffer,
  /// deliberately kept separate from the accuracy that adapts speed.
  int _sessionBufferedSeen = 0;
  int _sessionBufferedCorrect = 0;
  bool _currentBuffered = false;

  /// Paper mode: items copied this session (in order), each with the copy-time
  /// (audio-end → Done). Scored at session end.
  final List<({CurriculumItem item, int copyMs})> _paperItems = [];

  /// Paper scoring: one text controller per copied item (learner's entry).
  final List<TextEditingController> _paperEntries = [];

  /// Change in adaptive effective-WPM applied at the last session end (+1/0/-1),
  /// shown in the recap.
  int _lastSpeedDelta = 0;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(AdaptivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent resolves storageDir asynchronously, so it can arrive AFTER
    // this page first mounts. If it appears (or changes) later, wire up the
    // store now and reload — otherwise persistence silently no-ops and sessions
    // are never saved. Only reload when not mid-session.
    if (!_running &&
        widget.storageDir?.path != oldWidget.storageDir?.path &&
        widget.storageDir != null) {
      _attachStoreAndReload();
    }
  }

  Future<void> _init() async {
    _curriculum = buildCurriculum(widget.settings.callsign);
    _curriculumById = curriculumById(_curriculum);
    _generator = CopyGenerator(seed: 1, myCallsign: widget.settings.callsign);
    await _attachStoreAndReload();
  }

  /// (Re)attaches the progress store from the current [widget.storageDir] and
  /// loads persisted progress into the scheduler. Safe to call more than once.
  Future<void> _attachStoreAndReload() async {
    if (widget.storageDir != null) {
      _store = ProgressStore(File(
          '${widget.storageDir!.path}${Platform.pathSeparator}adaptive_progress.json'));
      _progress = await _store!.load();
    }
    _scheduler = SrsScheduler(
      states: _progress.itemStates,
      repCounter: _progress.totalReps,
    );
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _bufferTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
    _answerController.dispose();
    _answerFocus.dispose();
    for (final c in _paperEntries) {
      c.dispose();
    }
    _player.dispose();
    // Best-effort final flush — skipped if a reset just wiped the file, so we
    // don't resurrect deleted progress from this outgoing instance.
    if (suppressNextDisposeFlush) {
      suppressNextDisposeFlush = false;
    } else {
      _persist(immediate: true);
    }
    super.dispose();
  }

  // ---- SRS plumbing ----

  /// Ids already introduced (have SRS state with reps > 0).
  List<String> get _introducedIds =>
      _scheduler.states.entries.where((e) => e.value.introduced).map((e) => e.key).toList();

  /// The next curriculum item not yet introduced, with its prereq ids.
  ({String id, List<String> prereqs})? _nextLocked() {
    for (final it in _curriculum) {
      final st = _scheduler.states[it.id];
      if (st == null || !st.introduced) {
        return (id: it.id, prereqs: it.prereqs);
      }
    }
    return null; // fixed curriculum exhausted → generator takes over
  }

  /// True once every fixed-curriculum item has been introduced.
  bool get _curriculumExhausted => _nextLocked() == null;

  Future<void> _persist({bool immediate = false}) async {
    // Belt-and-suspenders: if the store wasn't wired up at mount (storageDir
    // resolves asynchronously), attach it now so a save is never silently
    // dropped. Attach without reloading — we must keep the in-memory progress
    // we're about to write, not overwrite it with a stale/empty file.
    if (_store == null && widget.storageDir != null) {
      _store = ProgressStore(File(
          '${widget.storageDir!.path}${Platform.pathSeparator}adaptive_progress.json'));
    }
    if (_store == null) return;
    _progress.totalReps = _scheduler.repCounter;
    // Generated items are ephemeral drill — never persist their SRS state, so
    // the states map can't grow unbounded and progress counts stay clean.
    _progress.itemStates.removeWhere((id, _) => isGeneratedId(id));
    if (immediate) {
      await _store!.flush(_progress);
    } else {
      await _store!.save(_progress);
    }
  }

  // ---- Session control ----

  Future<void> _toggleRun() async {
    if (_running) {
      await _endSession();
      return;
    }
    setState(() {
      _running = true;
      _sessionSeen = 0;
      _sessionCorrect = 0;
      _sessionBufferedSeen = 0;
      _sessionBufferedCorrect = 0;
      _sessionLatencies.clear();
      _sessionUnlockedIds.clear();
      _generatedThisSession.clear();
      _paperItems.clear();
      _sessionStart = widget.now();
      _remainingSeconds = widget.settings.sessionLengthMinutes * 60;
      _current = null;
      _lastCorrect = null;
      _lastLatencyMs = null;
    });
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    if (widget.settings.sessionLengthMinutes > 0) {
      _sessionTimer = Timer(Duration(minutes: widget.settings.sessionLengthMinutes), () {
        if (_running && mounted) _endSession();
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_running) return;
        setState(() {
          if (_remainingSeconds > 0) _remainingSeconds--;
        });
      });
    }
    _presentNext();
  }

  Future<void> _endSession() async {
    _completeSub?.cancel();
    _bufferTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    _stopElapsedBar();
    await _player.stop();
    _latencyWatch.stop();
    _latencyWatch.reset();

    // Paper mode: don't finalize yet — the learner still has to enter what they
    // wrote so we can score it. Move to the scoring screen.
    if (widget.settings.paperMode && _paperItems.isNotEmpty) {
      _openPaperScoring();
      return;
    }

    await _finalizeSession();
    if (!mounted) return;
    setState(() {
      _running = false;
      _phase = _Phase.idle;
    });
    if (_sessionSeen > 0) _showRecap();
  }

  /// Records the session summary and adapts speed from the tallies gathered so
  /// far (typed mode fills these live; paper mode fills them during scoring).
  Future<void> _finalizeSession() async {
    if (_sessionSeen == 0) return;
    final sorted = [..._sessionLatencies]..sort();
    final median = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
    final duration = _sessionStart == null
        ? 0
        : widget.now().difference(_sessionStart!).inSeconds;
    final accuracy = _sessionSeen == 0 ? 0.0 : _sessionCorrect / _sessionSeen;
    _progress.sessions.add(SessionSummary(
      endedAtMs: widget.now().millisecondsSinceEpoch,
      durationSeconds: duration,
      targetSeconds: widget.settings.sessionLengthMinutes * 60,
      itemsSeen: _sessionSeen,
      correct: _sessionCorrect,
      medianLatencyMs: median,
      unlockedIds: List.of(_sessionUnlockedIds),
    ));
    // Speed only ramps on TYPED recognition (writing ≠ recognizing). In paper
    // mode _sessionLatencies stays empty, so median is 0 and the ramp holds.
    final prevWpm = _progress.effectiveWpm;
    _progress.effectiveWpm = adaptEffectiveWpm(
      current: _progress.effectiveWpm,
      itemsSeen: widget.settings.paperMode ? 0 : _sessionSeen,
      accuracy: accuracy,
      medianLatencyMs: median,
    );
    _lastSpeedDelta = _progress.effectiveWpm - prevWpm;

    // Adapt the copy-behind buffer on its own retention signal: how accurate
    // you were WITH the buffer active this session (not overall accuracy, which
    // drives speed). Gated on mastered-item count.
    final mastered = summarize(_scheduler, curriculum: _curriculum).mastered;
    final bufferedAcc = _sessionBufferedSeen == 0
        ? 1.0
        : _sessionBufferedCorrect / _sessionBufferedSeen;
    _progress.bufferMs = adaptBufferMs(
      current: _progress.bufferMs,
      masteredCount: mastered,
      bufferedItems: _sessionBufferedSeen,
      bufferedAccuracy: bufferedAcc,
    );
    await _persist(immediate: true);
  }

  // ---- Paper-mode end-of-session scoring ----

  void _openPaperScoring() {
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    for (final c in _paperEntries) {
      c.dispose();
    }
    _paperEntries
      ..clear()
      ..addAll(List.generate(_paperItems.length, (_) => TextEditingController()));
    setState(() => _phase = _Phase.paperScoring);
  }

  /// Grades every paper entry against what was played, feeds the SRS, then
  /// finalizes and shows the recap.
  Future<void> _scorePaper() async {
    // Whole paper session shared one buffer value; if it was active, every
    // scored item counts toward the buffer's retention signal.
    final buffered = _progress.bufferMs > 0;
    for (var i = 0; i < _paperItems.length; i++) {
      final entry = _paperItems[i];
      final typed = _normalize(_paperEntries[i].text);
      final target = _normalize(entry.item.text);
      final correct = typed == target;
      // Copy-time is the latency; it never satisfies the ICR gate (writing is
      // slower), so paper advances items on accuracy but not on speed.
      _scheduler.grade(id: entry.item.id, correct: correct, latencyMs: entry.copyMs);
      _sessionSeen++;
      if (correct) _sessionCorrect++;
      if (buffered && correct) _sessionBufferedCorrect++;
    }
    await _finalizeSession();
    if (!mounted) return;
    setState(() {
      _running = false;
      _phase = _Phase.idle;
    });
    _showRecap();
  }

  void _showRecap() {
    final acc = _sessionSeen == 0 ? 0.0 : _sessionCorrect / _sessionSeen;
    final sorted = [..._sessionLatencies]..sort();
    final median = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _recapRow('Items', '$_sessionSeen'),
            _recapRow('Accuracy', '${(acc * 100).round()}%'),
            _recapRow('Median response', '${median}ms'),
            _recapRow('New items unlocked', '${_sessionUnlockedIds.length}'),
            _recapRow('Speed', '${_progress.effectiveWpm} WPM'
                '${_lastSpeedDelta > 0 ? ' ↑' : _lastSpeedDelta < 0 ? ' ↓' : ''}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _recapRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
        ),
      );

  // ---- Presentation loop ----

  /// Generated items presented this session, kept so a re-picked generated id
  /// (for spaced-repetition review) can be resolved back to its item.
  final Map<String, CurriculumItem> _generatedThisSession = {};

  Future<void> _presentNext() async {
    if (!_running) return;

    CurriculumItem? item;

    // Once the fixed curriculum is exhausted, mostly serve fresh generated
    // material, still interleaving spaced-repetition review of learned items.
    if (_curriculumExhausted && _shouldGenerate()) {
      item = _generator.next();
      _generatedThisSession[item.id] = item;
    } else {
      final introduced = _introducedIds;
      final before = introduced.length;
      final pick = _scheduler.pickNext(
        introducedIds: introduced,
        nextLockedItem: _nextLocked(),
      );
      if (pick == null) {
        // No curriculum item to serve → fall through to a generated one so we
        // never stall.
        item = _generator.next();
        _generatedThisSession[item.id] = item;
      } else {
        item = _curriculumById[pick] ?? _generatedThisSession[pick];
        if (item == null) {
          // A stale/unknown id (e.g. a generated id no longer cached) — skip.
          _presentNext();
          return;
        }
        // Track a genuinely new *curriculum* unlock (not generated review).
        final wasIntroduced = _scheduler.states[pick]?.introduced ?? false;
        if (!wasIntroduced && before > 0 && !isGeneratedId(pick)) {
          _sessionUnlockedIds.add(pick);
        }
      }
    }

    setState(() {
      _current = item;
      _phase = _Phase.playing;
      _answerController.clear();
      _lastCorrect = null;
      _lastLatencyMs = null;
      _recognitionLatencyMs = null;
    });

    await _playCurrent();
  }

  /// After the curriculum is done, decide whether to serve a fresh generated
  /// item vs. a spaced-repetition review of a learned item. Bias toward new
  /// generated material but keep reviewing so mastered items stay sharp.
  bool _shouldGenerate() {
    // ~70% generated, ~30% review. Vary by rep counter so it isn't periodic.
    return (_scheduler.repCounter * 7) % 10 < 7;
  }

  Future<void> _playCurrent() async {
    final item = _current;
    if (item == null || !_running) return;
    final wavPath = await renderMorseWavFile(
      text: item.text,
      actualWpm: kFixedActualWpm,
      effectiveWpm: _progress.effectiveWpm,
      effectiveMode: EffectiveSpeedMode.farnsworth,
      frequencyHz: widget.settings.frequencyHz.toDouble(),
      fileName: 'cw_adaptive.wav',
    );
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!_running) return;
      _onAudioComplete();
    });
    await _player.stop();
    await _player.play(DeviceFileSource(wavPath));
  }

  void _onAudioComplete() {
    // The copy-behind buffer: silent pause before the learner answers. Adaptive
    // and app-controlled (0 until instant recognition is established, then it
    // grows — see adaptBufferMs). Each buffered item is tallied so the buffer
    // can adapt on a retention-specific signal, separate from speed.
    final buffer = _progress.bufferMs;
    _currentBuffered = buffer > 0;
    if (_currentBuffered) _sessionBufferedSeen++;
    _bufferTimer?.cancel();
    setState(() => _phase = _Phase.buffering);
    _bufferTimer = Timer(Duration(milliseconds: buffer), () {
      if (!mounted || !_running) return;
      setState(() => _phase =
          widget.settings.paperMode ? _Phase.paperCopy : _Phase.awaitingInput);
      _latencyWatch
        ..reset()
        ..start();
      _startElapsedBar();
    });
  }

  /// Paper mode: learner has written the answer and tapped Done. Record the
  /// copy-time, stash the item for end-of-session scoring, and move on — the
  /// answer is never revealed mid-session.
  void _onPaperDone() {
    if (_phase != _Phase.paperCopy) return;
    _latencyWatch.stop();
    _stopElapsedBar();
    final copyMs = _latencyWatch.elapsedMilliseconds;
    final item = _current!;
    _paperItems.add((item: item, copyMs: copyMs));
    AdaptiveProgress.pushCapped(_progress.recentPaperMs, copyMs);
    _presentNext();
  }

  /// Starts the adaptive "too long" bar for the current item. The target is
  /// personalised to the learner's own recent pace (typed vs. paper history)
  /// rather than a fixed constant, so it tightens as they speed up.
  void _startElapsedBar() {
    final chars = (_current?.text ?? '').replaceAll(' ', '').length;
    final paper = widget.settings.paperMode;
    _elapsedTargetMs = elapsedTargetMs(
      history: paper ? _progress.recentPaperMs : _progress.recentTypedMs,
      charCount: chars,
      // Paper allows more time (writing is slower) and has no ICR floor.
      margin: paper ? 1.5 : 1.7,
      floorMs: paper ? 0 : kIcrLatencyMs,
      fallbackPerCharMs: paper ? 1200 : kIcrLatencyMs,
    );
    _elapsedWatch
      ..reset()
      ..start();
    _elapsedTimer?.cancel();
    // Tick ~30fps for a smooth bar; stop once we're a bit past target.
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted ||
          (_phase != _Phase.awaitingInput && _phase != _Phase.paperCopy)) {
        return;
      }
      if (_elapsedWatch.elapsedMilliseconds > _elapsedTargetMs + 1500) {
        _elapsedTimer?.cancel();
      }
      setState(() {}); // repaint the bar
    });
  }

  void _stopElapsedBar() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsedWatch.stop();
  }

  void _replay() {
    if (_current == null) return;
    _playReplayOnly();
  }

  Future<void> _playReplayOnly() async {
    final item = _current;
    if (item == null) return;
    final wavPath = await renderMorseWavFile(
      text: item.text,
      actualWpm: kFixedActualWpm,
      effectiveWpm: _progress.effectiveWpm,
      effectiveMode: EffectiveSpeedMode.farnsworth,
      frequencyHz: widget.settings.frequencyHz.toDouble(),
      fileName: 'cw_adaptive_replay.wav',
    );
    // Use a fresh play without disturbing the completion subscription state.
    await _player.stop();
    await _player.play(DeviceFileSource(wavPath));
  }

  /// Captures recognition latency at the first keystroke only.
  void _onAnswerChanged(String value) {
    if (_recognitionLatencyMs == null && value.isNotEmpty && _latencyWatch.isRunning) {
      _recognitionLatencyMs = _latencyWatch.elapsedMilliseconds;
    }
  }

  // ---- CW keyboard handlers (system keyboard is suppressed) ----

  void _onCwKey(String ch) {
    if (_phase != _Phase.awaitingInput) return;
    _answerController.text = _answerController.text + ch;
    _onAnswerChanged(_answerController.text);
    setState(() {}); // reflect the new character
  }

  void _onCwBackspace() {
    if (_phase != _Phase.awaitingInput) return;
    final t = _answerController.text;
    if (t.isEmpty) return;
    _answerController.text = t.substring(0, t.length - 1);
    setState(() {});
  }

  void _submit() {
    if (_phase != _Phase.awaitingInput) return;
    _latencyWatch.stop();
    _stopElapsedBar();
    // Recognition = time to first keystroke. If they submitted an empty answer
    // (or hit Enter with no typing), fall back to the full elapsed time.
    final latency = _recognitionLatencyMs ?? _latencyWatch.elapsedMilliseconds;
    final item = _current!;
    final typed = _normalize(_answerController.text);
    final target = _normalize(item.text);
    final correct = typed == target;

    _scheduler.grade(id: item.id, correct: correct, latencyMs: latency);
    _sessionSeen++;
    if (correct) _sessionCorrect++;
    if (_currentBuffered && correct) _sessionBufferedCorrect++;
    _sessionLatencies.add(latency);
    // Feed the adaptive typed-mode bar's history.
    AdaptiveProgress.pushCapped(_progress.recentTypedMs, latency);
    // Write immediately so progress survives a hot restart / hard kill (neither
    // calls dispose). The blob is ~1KB; there's no need to debounce per item.
    _persist(immediate: true);

    setState(() {
      _phase = _Phase.revealed;
      _lastCorrect = correct;
      _lastLatencyMs = latency;
    });
  }

  void _continue() {
    if (_phase != _Phase.revealed) return;
    _presentNext();
  }

  String _normalize(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Set of characters accepted from a physical keyboard (matches the on-screen
  /// CW keyboard's key set).
  static final Set<String> _cwChars = {
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split(''),
    '.', ',', '/', '?', ' ',
  };

  /// Routes physical-keyboard input to the same handlers the on-screen CW
  /// keyboard uses, so a hardware keyboard works while the CW keyboard is up.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // Enter: submit during input, advance on the reveal screen.
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_phase == _Phase.awaitingInput) {
        _submit();
        return KeyEventResult.handled;
      }
      if (_phase == _Phase.revealed) {
        _continue();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_phase != _Phase.awaitingInput) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.backspace) {
      _onCwBackspace();
      return KeyEventResult.handled;
    }

    // Character keys (uppercased, only if it's a valid CW glyph).
    final ch = event.character?.toUpperCase();
    if (ch != null && ch.length == 1 && _cwChars.contains(ch)) {
      _onCwKey(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      // SafeArea keeps the Start button clear of the bottom home indicator.
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildStage(theme)),
              const SizedBox(height: 16),
              _buildControls(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage(ThemeData theme) {
    final container = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    );

    if (!_running) {
      return _buildIdleScreen(theme);
    }

    switch (_phase) {
      case _Phase.playing:
        return _centered(container, theme, icon: Icons.volume_up, label: 'Listen…');
      case _Phase.buffering:
        return _centered(container, theme, icon: Icons.hourglass_top, label: 'Hold it…');
      case _Phase.awaitingInput:
        return _buildInput(container, theme);
      case _Phase.paperCopy:
        return _buildPaperCopy(container, theme);
      case _Phase.paperScoring:
        return _buildPaperScoring(container, theme);
      case _Phase.revealed:
        return _buildReveal(container, theme);
      case _Phase.idle:
        return _centered(container, theme, icon: Icons.more_horiz, label: '');
    }
  }

  Widget _buildPaperCopy(BoxDecoration d, ThemeData theme) {
    return Container(
      decoration: d,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 48, color: theme.hintColor),
          const SizedBox(height: 12),
          Text('Write what you heard', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('on paper — you\'ll enter it at the end',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 20),
          _buildElapsedBar(theme),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _onPaperDone,
            icon: const Icon(Icons.check),
            label: const Text('Done'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperScoring(BoxDecoration d, ThemeData theme) {
    return Container(
      decoration: d,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter what you wrote', style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Type each item from your paper, then score.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: _paperItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _paperEntries[i],
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        hintText: 'item ${i + 1}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scorePaper,
            icon: const Icon(Icons.grading),
            label: const Text('Score all'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleScreen(ThemeData theme) {
    final sessions = _progress.sessions;
    // Generous window; the heatmap shows the most recent weeks that fit width.
    final days = dailyActivity(sessions, today: widget.now(), days: 259, wholeWeeks: true);
    final anyActivity = days.any((d) => d.active);
    final items = itemProgressList(_scheduler, curriculum: _curriculum);
    final unlockedCount =
        items.where((p) => p.status != ItemStatus.locked).length;
    final lockedColor = theme.disabledColor.withValues(alpha: 0.15);
    final nudge = milestoneNudge(_scheduler, _curriculum);

    // No boxed "stage" on the home screen — content sits on the page so it
    // breathes. The framed stage is reserved for the in-session task.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Progress: speed & accuracy trend (the skill that matters) ----
            _sectionLabel(theme, 'Progress', null),
            const SizedBox(height: 8),
            if (sessions.length >= 2)
              SessionTrendChart(sessions: sessions)
            else
              _hint(theme, sessions.isEmpty
                  ? 'Finish a couple of timed sessions to see your trend.'
                  : 'One more session and your trend appears here.'),

            // ---- Quiet scope line (breadth, deliberately understated) ----
            const SizedBox(height: 12),
            Center(
              child: Text(
                nudge != null
                    ? '$unlockedCount items in rotation · $nudge'
                    : '$unlockedCount items in rotation',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),

            // ---- Daily activity ----
            const Divider(height: 24),
            _sectionLabel(theme, 'Daily activity', 'last 20 weeks'),
            const SizedBox(height: 8),
            if (anyActivity)
              ActivityHeatmap(days: days)
            else
              _hint(theme, 'Practice on more days to build a streak.'),

            // ---- Unlocked items (locked ones collapsed to a count so the
            //      curriculum order is never revealed — no priming). ----
            const Divider(height: 24),
            Row(
              children: [
                Expanded(child: _sectionLabel(theme, 'Unlocked', null)),
                _legendDot(theme, kMasteredColor, 'mastered'),
                const SizedBox(width: 8),
                _legendDot(theme, kLearningColor, 'learning'),
              ],
            ),
            const SizedBox(height: 8),
            _buildUnlockedItems(theme, items, lockedColor),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Shows unlocked items individually (tappable), then collapses the still-
  /// locked items into a single count so their curriculum order is never
  /// revealed (which would prime the learner on what's coming next).
  Widget _buildUnlockedItems(
      ThemeData theme, List<ItemProgress> items, Color lockedColor) {
    final unlocked =
        items.where((p) => p.status != ItemStatus.locked).toList();
    final lockedCount = items.length - unlocked.length;

    if (unlocked.isEmpty) {
      return _hint(theme, 'Press Start — your first items unlock right away. '
          '$lockedCount more await.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ItemMap(items: unlocked),
        if (lockedCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: lockedColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 14, color: theme.hintColor),
                const SizedBox(width: 6),
                Text('$lockedCount more to unlock',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String title, String? trailing) {
    return Row(
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ],
      ],
    );
  }

  Widget _hint(ThemeData theme, String text) => Text(text,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor));

  Widget _legendDot(ThemeData theme, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      );


  Widget _centered(BoxDecoration d, ThemeData theme,
      {required IconData icon, required String label}) {
    return Container(
      decoration: d,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.hintColor),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(label, style: theme.textTheme.titleLarge),
          ],
        ],
      ),
    );
  }

  Widget _buildInput(BoxDecoration d, ThemeData theme) {
    final typed = _answerController.text;
    return Container(
      decoration: d,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        children: [
          const Spacer(),
          Text('What did you hear?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          // Read-only answer display (system keyboard suppressed; input comes
          // from the CW keyboard below).
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              typed.isEmpty ? ' ' : typed,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildElapsedBar(theme),
          const Spacer(),
          CwKeyboard(
            onKey: _onCwKey,
            onBackspace: _onCwBackspace,
            onEnter: _submit,
          ),
        ],
      ),
    );
  }

  /// The "too long to answer" bar. Fills as time passes toward the per-item
  /// target; turns red once you're over. Purely motivational — no auto-submit.
  Widget _buildElapsedBar(ThemeData theme) {
    final elapsed = _elapsedWatch.elapsedMilliseconds;
    final frac = (elapsed / _elapsedTargetMs).clamp(0.0, 1.0);
    final over = elapsed > _elapsedTargetMs;
    final color = over
        ? theme.colorScheme.error
        : Color.lerp(kMasteredColor, kLearningColor, frac)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 6,
            backgroundColor: theme.disabledColor.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          over ? 'Too slow — but finish it' : 'Answer before the bar fills',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: over ? theme.colorScheme.error : theme.hintColor,
          ),
        ),
      ],
    );
  }

  Widget _buildReveal(BoxDecoration d, ThemeData theme) {
    final correct = _lastCorrect ?? false;
    final fast = (_lastLatencyMs ?? 1 << 30) <= kIcrLatencyMs;
    final color = correct ? Colors.green : theme.colorScheme.error;
    return Container(
      decoration: d,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(correct ? Icons.check_circle : Icons.cancel, color: color, size: 40),
          const SizedBox(height: 12),
          Text(
            _current?.text ?? '',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (!correct && _answerController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('you typed: ${_answerController.text.trim().toUpperCase()}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
          ],
          const SizedBox(height: 12),
          Text(
            correct
                ? (fast ? '${_lastLatencyMs}ms · instant ✓' : '${_lastLatencyMs}ms · keep speeding up')
                : 'Let it go — you\'ll see it again soon.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _replay,
                icon: const Icon(Icons.replay),
                label: const Text('Hear it'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _continue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    // Physical-keyboard Enter is handled by the page-level Focus (_handleKey).
    return FilledButton.icon(
      onPressed: _toggleRun,
      icon: Icon(_running ? Icons.stop : Icons.play_arrow),
      label: Text(_running ? _stopLabel : 'Start'),
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
    );
  }

  String get _stopLabel {
    if (widget.settings.sessionLengthMinutes == 0) return 'Stop';
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return 'Stop ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
