/// Persistence for adaptive "Copy" mode: per-item SRS state and a session log.
///
/// Stored as a single JSON file rather than in shared_preferences because the
/// per-item state map and session history would bloat key-value storage. The
/// file lives in the same user-editable assets directory used elsewhere, so it
/// travels with the app's other data.
///
/// The store is IO-injectable (takes a [File]) so it can be unit-tested against
/// a temp directory without pulling in path_provider / platform channels.
library;

import 'dart:convert';
import 'dart:io';

import 'srs.dart';

/// One completed practice session's summary — the substrate for a future
/// history/calendar view (TODO.md "practice session logging").
class SessionSummary {
  /// Wall-clock ms since epoch when the session ended.
  final int endedAtMs;
  final int durationSeconds;

  /// The configured session length (seconds) this session was aiming for, or 0
  /// if the session was unlimited. Lets a chart show duration as a fraction of
  /// a full session (a completed fixed-length session == 100%).
  final int targetSeconds;

  final int itemsSeen;
  final int correct;
  final int medianLatencyMs;

  /// Curriculum ids introduced for the first time during this session.
  final List<String> unlockedIds;

  SessionSummary({
    required this.endedAtMs,
    required this.durationSeconds,
    this.targetSeconds = 0,
    required this.itemsSeen,
    required this.correct,
    required this.medianLatencyMs,
    List<String>? unlockedIds,
  }) : unlockedIds = unlockedIds ?? const [];

  double get accuracy => itemsSeen == 0 ? 0 : correct / itemsSeen;

  int get newItemsUnlocked => unlockedIds.length;

  /// Fraction of a full (target-length) session actually practised, 0..1.
  /// Returns 1.0 for unlimited sessions (no target to measure against).
  double get durationFraction {
    if (targetSeconds <= 0) return 1.0;
    return (durationSeconds / targetSeconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'endedAtMs': endedAtMs,
        'durationSeconds': durationSeconds,
        'targetSeconds': targetSeconds,
        'itemsSeen': itemsSeen,
        'correct': correct,
        'medianLatencyMs': medianLatencyMs,
        'unlockedIds': unlockedIds,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> j) => SessionSummary(
        endedAtMs: (j['endedAtMs'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
        targetSeconds: (j['targetSeconds'] as num?)?.toInt() ?? 0,
        itemsSeen: (j['itemsSeen'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        medianLatencyMs: (j['medianLatencyMs'] as num?)?.toInt() ?? 0,
        unlockedIds:
            (j['unlockedIds'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );
}

/// Starting effective (Farnsworth) speed for a brand-new learner. Character
/// speed is fixed (see [kFixedActualWpm]); only this ramps up.
const int kStartEffectiveWpm = 12;

/// Fixed character speed for Copy mode — learn at target speed from day one
/// (Koch). Only the effective/Farnsworth speed adapts.
const int kFixedActualWpm = 20;

/// The full persisted blob for adaptive mode.
class AdaptiveProgress {
  final Map<String, ItemState> itemStates;
  final List<SessionSummary> sessions;

  /// Total presentations across all sessions (persisted repCounter) so that
  /// due scheduling stays monotonic across app restarts.
  int totalReps;

  /// Current adaptive effective (Farnsworth) speed in WPM. The app raises this
  /// as recognition gets fast & accurate, and eases it back if it hurts.
  int effectiveWpm;

  /// Current adaptive copy-behind buffer (ms) — the silent pause after audio
  /// before you answer. 0 until instant recognition is established, then it
  /// grows as an advanced retention skill. See adaptBufferMs.
  int bufferMs;

  /// Recent per-item TYPED recognition times (ms), newest last, capped. Drives
  /// the adaptive "too slow" bar in typed mode.
  final List<int> recentTypedMs;

  /// Recent per-item PAPER copy times (ms) — audio-end → Done tap, newest last,
  /// capped. Drives the adaptive bar in paper mode (separate from typed).
  final List<int> recentPaperMs;

  AdaptiveProgress({
    Map<String, ItemState>? itemStates,
    List<SessionSummary>? sessions,
    this.totalReps = 0,
    this.effectiveWpm = kStartEffectiveWpm,
    this.bufferMs = 0,
    List<int>? recentTypedMs,
    List<int>? recentPaperMs,
  })  : itemStates = itemStates ?? <String, ItemState>{},
        sessions = sessions ?? <SessionSummary>[],
        recentTypedMs = recentTypedMs ?? <int>[],
        recentPaperMs = recentPaperMs ?? <int>[];

  /// Appends a per-item time to a capped rolling history (keeps the last 30).
  static void pushCapped(List<int> history, int ms) {
    history.add(ms);
    while (history.length > 30) {
      history.removeAt(0);
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'totalReps': totalReps,
        'effectiveWpm': effectiveWpm,
        'bufferMs': bufferMs,
        'recentTypedMs': recentTypedMs,
        'recentPaperMs': recentPaperMs,
        'itemStates': itemStates.map((k, v) => MapEntry(k, v.toJson())),
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory AdaptiveProgress.fromJson(Map<String, dynamic> j) {
    final rawStates = (j['itemStates'] as Map?) ?? {};
    return AdaptiveProgress(
      totalReps: (j['totalReps'] as num?)?.toInt() ?? 0,
      effectiveWpm: (j['effectiveWpm'] as num?)?.toInt() ?? kStartEffectiveWpm,
      bufferMs: (j['bufferMs'] as num?)?.toInt() ?? 0,
      recentTypedMs: (j['recentTypedMs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          <int>[],
      recentPaperMs: (j['recentPaperMs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          <int>[],
      itemStates: rawStates.map(
        (k, v) => MapEntry(
            k as String, ItemState.fromJson((v as Map).cast<String, dynamic>())),
      ),
      sessions: ((j['sessions'] as List?) ?? [])
          .map((e) => SessionSummary.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Loads/saves [AdaptiveProgress] to a JSON file. Saves are debounced so the
/// adaptive loop can call [save] freely after every rep.
class ProgressStore {
  final File file;
  final Duration debounce;

  ProgressStore(this.file, {this.debounce = const Duration(milliseconds: 750)});

  /// Reads the progress file. Returns an empty [AdaptiveProgress] if the file is
  /// missing or corrupt (so a bad write never bricks the mode).
  Future<AdaptiveProgress> load() async {
    try {
      if (!await file.exists()) return AdaptiveProgress();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AdaptiveProgress();
      return AdaptiveProgress.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return AdaptiveProgress();
    }
  }

  bool _writePending = false;
  AdaptiveProgress? _pending;

  /// Debounced write. Multiple calls within [debounce] collapse into one flush
  /// of the most recent snapshot.
  Future<void> save(AdaptiveProgress progress) async {
    _pending = progress;
    if (_writePending) return;
    _writePending = true;
    await Future.delayed(debounce);
    _writePending = false;
    final snapshot = _pending;
    _pending = null;
    if (snapshot != null) await flush(snapshot);
  }

  /// Immediate write, bypassing the debounce (use on session end / dispose).
  Future<void> flush(AdaptiveProgress progress) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(progress.toJson()), flush: true);
  }

  /// Deletes the progress file (reset-progress action).
  Future<void> reset() async {
    if (await file.exists()) await file.delete();
  }
}
