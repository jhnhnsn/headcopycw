/// Persistence for adaptive "Copy" mode: per-item SRS state and a session log.
///
/// Stored as a single JSON file rather than in shared_preferences because the
/// per-item state map and session history would bloat key-value storage. The
/// file lives in the same user-editable assets directory used elsewhere, so it
/// travels with the app's other data. Web has no filesystem, so there the same
/// blob goes in shared_preferences (localStorage) instead.
///
/// The store is IO-injectable (takes a [File]) so it can be unit-tested against
/// a temp directory without pulling in path_provider / platform channels.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

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
/// speed is fixed (see [kFixedActualWpm]); only this ramps up. Set to 15 (not a
/// lower value) so the Farnsworth padding between letters is modest from the
/// outset — much closer to real on-air spacing — then it tightens to 20 (no
/// padding) as recognition gets fast and accurate.
const int kStartEffectiveWpm = 15;

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

  /// Recent per-item recognition times (ms), newest last, capped. Drives the
  /// adaptive "too slow" bar.
  final List<int> recentTypedMs;

  /// Per-character rolling correctness observed inside any item (from typed
  /// per-character diffs). char → recent bools. Drives weak-char reinforcement
  /// and confusable practice from mistakes made INSIDE words, not just solo
  /// characters. See SrsScheduler.charRecent.
  final Map<String, List<bool>> charRecent;

  AdaptiveProgress({
    Map<String, ItemState>? itemStates,
    List<SessionSummary>? sessions,
    this.totalReps = 0,
    this.effectiveWpm = kStartEffectiveWpm,
    this.bufferMs = 0,
    List<int>? recentTypedMs,
    Map<String, List<bool>>? charRecent,
  })  : itemStates = itemStates ?? <String, ItemState>{},
        sessions = sessions ?? <SessionSummary>[],
        recentTypedMs = recentTypedMs ?? <int>[],
        charRecent = charRecent ?? <String, List<bool>>{};

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
        'charRecent': charRecent,
        'itemStates': itemStates.map((k, v) => MapEntry(k, v.toJson())),
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory AdaptiveProgress.fromJson(Map<String, dynamic> j) {
    final rawStates = (j['itemStates'] as Map?) ?? {};
    final rawChar = (j['charRecent'] as Map?) ?? {};
    return AdaptiveProgress(
      totalReps: (j['totalReps'] as num?)?.toInt() ?? 0,
      effectiveWpm: (j['effectiveWpm'] as num?)?.toInt() ?? kStartEffectiveWpm,
      bufferMs: (j['bufferMs'] as num?)?.toInt() ?? 0,
      recentTypedMs: (j['recentTypedMs'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          <int>[],
      charRecent: rawChar.map((k, v) => MapEntry(
          k as String, (v as List).map((e) => e as bool).toList())),
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

/// Where the serialized progress blob lives: a JSON file natively, or a
/// shared_preferences key (browser localStorage) on web, which has no
/// filesystem.
abstract class ProgressBackend {
  /// The stored JSON, or null if nothing has been saved.
  Future<String?> read();
  Future<void> write(String json);
  Future<void> delete();
}

class FileProgressBackend implements ProgressBackend {
  final File file;

  FileProgressBackend(this.file);

  @override
  Future<String?> read() async =>
      await file.exists() ? await file.readAsString() : null;

  @override
  Future<void> write(String json) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(json, flush: true);
  }

  @override
  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}

class PrefsProgressBackend implements ProgressBackend {
  static const String key = 'adaptive_progress';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(key, json);

  @override
  Future<void> delete() async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// Loads/saves [AdaptiveProgress] through a [ProgressBackend]. Saves are
/// debounced so the adaptive loop can call [save] freely after every rep.
class ProgressStore {
  final ProgressBackend backend;
  final Duration debounce;

  ProgressStore(File file, {Duration debounce = const Duration(milliseconds: 750)})
      : this.withBackend(FileProgressBackend(file), debounce: debounce);

  ProgressStore.withBackend(this.backend,
      {this.debounce = const Duration(milliseconds: 750)});

  /// Reads the stored progress. Returns an empty [AdaptiveProgress] if it is
  /// missing or corrupt (so a bad write never bricks the mode).
  Future<AdaptiveProgress> load() async {
    try {
      final raw = await backend.read();
      if (raw == null || raw.trim().isEmpty) return AdaptiveProgress();
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
  Future<void> flush(AdaptiveProgress progress) =>
      backend.write(jsonEncode(progress.toJson()));

  /// Deletes the stored progress (reset-progress action).
  Future<void> reset() => backend.delete();
}
