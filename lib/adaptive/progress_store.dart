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
  final int itemsSeen;
  final int correct;
  final int medianLatencyMs;

  /// Curriculum ids introduced for the first time during this session.
  final List<String> unlockedIds;

  SessionSummary({
    required this.endedAtMs,
    required this.durationSeconds,
    required this.itemsSeen,
    required this.correct,
    required this.medianLatencyMs,
    List<String>? unlockedIds,
  }) : unlockedIds = unlockedIds ?? const [];

  double get accuracy => itemsSeen == 0 ? 0 : correct / itemsSeen;

  int get newItemsUnlocked => unlockedIds.length;

  Map<String, dynamic> toJson() => {
        'endedAtMs': endedAtMs,
        'durationSeconds': durationSeconds,
        'itemsSeen': itemsSeen,
        'correct': correct,
        'medianLatencyMs': medianLatencyMs,
        'unlockedIds': unlockedIds,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> j) => SessionSummary(
        endedAtMs: (j['endedAtMs'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 0,
        itemsSeen: (j['itemsSeen'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        medianLatencyMs: (j['medianLatencyMs'] as num?)?.toInt() ?? 0,
        unlockedIds:
            (j['unlockedIds'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
      );
}

/// The full persisted blob for adaptive mode.
class AdaptiveProgress {
  final Map<String, ItemState> itemStates;
  final List<SessionSummary> sessions;

  /// Total presentations across all sessions (persisted repCounter) so that
  /// due scheduling stays monotonic across app restarts.
  int totalReps;

  AdaptiveProgress({
    Map<String, ItemState>? itemStates,
    List<SessionSummary>? sessions,
    this.totalReps = 0,
  })  : itemStates = itemStates ?? <String, ItemState>{},
        sessions = sessions ?? <SessionSummary>[];

  Map<String, dynamic> toJson() => {
        'version': 1,
        'totalReps': totalReps,
        'itemStates': itemStates.map((k, v) => MapEntry(k, v.toJson())),
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory AdaptiveProgress.fromJson(Map<String, dynamic> j) {
    final rawStates = (j['itemStates'] as Map?) ?? {};
    return AdaptiveProgress(
      totalReps: (j['totalReps'] as num?)?.toInt() ?? 0,
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
