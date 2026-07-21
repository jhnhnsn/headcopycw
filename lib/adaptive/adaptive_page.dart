import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../morse_engine.dart';
import 'curriculum.dart';
import 'curriculum_provider.dart';
import 'generator.dart';
import 'progress_page.dart';
import 'progress_stats.dart';
import 'progress_store.dart';
import 'srs.dart';

/// Minimal read-only view of the trainer settings the adaptive loop needs.
/// Mirrors fields on CwTrainerSettings so we avoid a circular import.
class AdaptiveSettings {
  final int actualWpm;
  final int effectiveWpm;
  final EffectiveSpeedMode effectiveMode;
  final int frequencyHz;

  /// Delay after audio ends before the answer field appears (buffer / "copy
  /// behind" window). Reuses the existing displayDelayMs setting semantics.
  final int bufferDelayMs;

  /// Session length in minutes (0 = unlimited).
  final int sessionLengthMinutes;

  /// The learner's own callsign (uppercase, encodable), or '' if unset.
  final String callsign;

  const AdaptiveSettings({
    required this.actualWpm,
    required this.effectiveWpm,
    required this.effectiveMode,
    required this.frequencyHz,
    required this.bufferDelayMs,
    required this.sessionLengthMinutes,
    this.callsign = '',
  });
}

/// Lifecycle phases of one presentation.
enum _Phase { idle, playing, buffering, awaitingInput, revealed }

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
    _answerController.dispose();
    _answerFocus.dispose();
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
      _sessionLatencies.clear();
      _sessionUnlockedIds.clear();
      _generatedThisSession.clear();
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
    await _player.stop();
    _latencyWatch.stop();
    _latencyWatch.reset();

    // Record a session summary if anything happened.
    if (_sessionSeen > 0) {
      final sorted = [..._sessionLatencies]..sort();
      final median = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
      final duration = _sessionStart == null
          ? 0
          : widget.now().difference(_sessionStart!).inSeconds;
      _progress.sessions.add(SessionSummary(
        endedAtMs: widget.now().millisecondsSinceEpoch,
        durationSeconds: duration,
        itemsSeen: _sessionSeen,
        correct: _sessionCorrect,
        medianLatencyMs: median,
        unlockedIds: List.of(_sessionUnlockedIds),
      ));
      await _persist(immediate: true);
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _phase = _Phase.idle;
    });
    if (_sessionSeen > 0) _showRecap();
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
      actualWpm: widget.settings.actualWpm,
      effectiveWpm: widget.settings.effectiveWpm,
      effectiveMode: widget.settings.effectiveMode,
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
    // Start the buffer beat, then reveal the input field and start the clock.
    _bufferTimer?.cancel();
    setState(() => _phase = _Phase.buffering);
    _bufferTimer = Timer(Duration(milliseconds: widget.settings.bufferDelayMs), () {
      if (!mounted || !_running) return;
      setState(() => _phase = _Phase.awaitingInput);
      _latencyWatch
        ..reset()
        ..start();
      _answerFocus.requestFocus();
    });
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
      actualWpm: widget.settings.actualWpm,
      effectiveWpm: widget.settings.effectiveWpm,
      effectiveMode: widget.settings.effectiveMode,
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

  void _submit() {
    if (_phase != _Phase.awaitingInput) return;
    _latencyWatch.stop();
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
    _sessionLatencies.add(latency);
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

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildStage(theme)),
          const SizedBox(height: 16),
          _buildControls(theme),
        ],
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
      return _buildIdleScreen(container, theme);
    }

    switch (_phase) {
      case _Phase.playing:
        return _centered(container, theme, icon: Icons.volume_up, label: 'Listen…');
      case _Phase.buffering:
        return _centered(container, theme, icon: Icons.hourglass_top, label: 'Hold it…');
      case _Phase.awaitingInput:
        return _buildInput(container, theme);
      case _Phase.revealed:
        return _buildReveal(container, theme);
      case _Phase.idle:
        return _centered(container, theme, icon: Icons.more_horiz, label: '');
    }
  }

  Widget _buildIdleScreen(BoxDecoration container, ThemeData theme) {
    final sessions = _progress.sessions;
    final lastSession = sessions.isEmpty ? null : sessions.last;
    final days = dailyActivity(sessions, today: widget.now(), days: 30);
    final anyActivity = days.any((d) => d.active);
    final items = itemProgressList(_scheduler, curriculum: _curriculum);
    final unlockedCount =
        items.where((p) => p.status != ItemStatus.locked).length;
    final lockedColor = theme.disabledColor.withValues(alpha: 0.15);
    final nudge = milestoneNudge(_scheduler, _curriculum);

    return Container(
      decoration: container,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Hero: last session's speed & accuracy (the current readout;
            //      the trend graph below shows the trajectory). ----
            _buildStatTiles(theme, lastSession),

            // ---- Trend ----
            const SizedBox(height: 16),
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
            _sectionLabel(theme, 'Daily activity', 'last 30 days'),
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

  /// Two big stat tiles showing your LAST session's accuracy and recognition
  /// speed — the immediate "how you just did" readout. The trend graph below
  /// carries the trajectory over time.
  Widget _buildStatTiles(ThemeData theme, SessionSummary? last) {
    final hasData = last != null && last.itemsSeen > 0;
    final acc = hasData ? '${(last.accuracy * 100).round()}%' : '—';
    final speed = hasData && last.medianLatencyMs > 0
        ? '${last.medianLatencyMs}ms'
        : '—';
    final fast = hasData && last.medianLatencyMs > 0 &&
        last.medianLatencyMs <= kIcrLatencyMs;
    return Column(
      children: [
        Text(hasData ? 'Last session' : 'Your last session',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _statTile(theme, 'ACCURACY', acc,
                Icons.check_circle_outline, kMasteredColor)),
            const SizedBox(width: 12),
            Expanded(child: _statTile(theme, 'SPEED', speed, Icons.bolt,
                fast ? kMasteredColor : theme.colorScheme.primary,
                footnote: fast ? 'instant' : null)),
          ],
        ),
      ],
    );
  }

  Widget _statTile(ThemeData theme, String label, String value, IconData icon,
      Color accent, {String? footnote}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 5),
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: accent, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (footnote != null)
            Text(footnote,
                style: theme.textTheme.bodySmall?.copyWith(color: accent)),
        ],
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
    return Container(
      decoration: d,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('What did you hear?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _answerController,
            focusNode: _answerFocus,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'type here',
            ),
            onChanged: _onAnswerChanged,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Check')),
        ],
      ),
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
    // Allow Enter to advance on the reveal screen too.
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            _phase == _Phase.revealed &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _continue();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FilledButton.icon(
        onPressed: _toggleRun,
        icon: Icon(_running ? Icons.stop : Icons.play_arrow),
        label: Text(_running ? _stopLabel : 'Start'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
    );
  }

  String get _stopLabel {
    if (widget.settings.sessionLengthMinutes == 0) return 'Stop';
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return 'Stop ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
