import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart' show resetWindowSize;
import 'morse_data.dart';
import 'morse_engine.dart';
import 'adaptive/adaptive_page.dart';

/// Returns the assets directory path for user-editable files.
/// On Windows/macOS/Linux, files are stored in application support directory.
/// On iOS/Android, files are stored in documents directory for user access.
/// Returns null on web (use bundled assets instead).
Future<Directory?> getAssetsDirectory() async {
  if (kIsWeb) {
    return null;
  }

  Directory appDir;
  if (Platform.isIOS || Platform.isAndroid) {
    // Use documents directory on mobile so users can access/edit files
    appDir = await getApplicationDocumentsDirectory();
  } else {
    appDir = await getApplicationSupportDirectory();
  }

  final assetsDir = Directory('${appDir.path}${Platform.pathSeparator}assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create(recursive: true);
  }
  return assetsDir;
}

const _assetFiles = [
  'cw-words.txt',
  'common-english-words.txt',
  'qsos.txt',
  'callsigns.txt',
  'HELP.md',
];

/// Copies bundled assets to the user's assets directory if they don't exist.
Future<void> initializeUserAssets() async {
  final assetsDir = await getAssetsDirectory();
  if (assetsDir == null) return;

  for (final fileName in _assetFiles) {
    final file = File('${assetsDir.path}${Platform.pathSeparator}$fileName');
    if (!await file.exists()) {
      try {
        final content = await rootBundle.loadString('assets/$fileName');
        await file.writeAsString(content);
      } catch (e) {
        // Asset not found or write failed, skip
      }
    }
  }
}

/// Resets all user assets to the bundled defaults.
Future<void> resetUserAssets() async {
  final assetsDir = await getAssetsDirectory();
  if (assetsDir == null) return;

  for (final fileName in _assetFiles) {
    final file = File('${assetsDir.path}${Platform.pathSeparator}$fileName');
    try {
      final content = await rootBundle.loadString('assets/$fileName');
      await file.writeAsString(content);
    } catch (e) {
      // Asset not found or write failed, skip
    }
  }
}

/// Deletes the adaptive "Copy" mode progress file, resetting all SRS state.
Future<void> resetAdaptiveProgress() async {
  final assetsDir = await getAssetsDirectory();
  if (assetsDir == null) return;
  final file =
      File('${assetsDir.path}${Platform.pathSeparator}adaptive_progress.json');
  if (await file.exists()) await file.delete();
}

/// Loads a text file, preferring the user's copy if available.
Future<String> loadAssetFile(String fileName) async {
  final assetsDir = await getAssetsDirectory();
  if (assetsDir != null) {
    final file = File('${assetsDir.path}${Platform.pathSeparator}$fileName');
    if (await file.exists()) {
      return await file.readAsString();
    }
  }
  // Fall back to bundled asset
  return await rootBundle.loadString('assets/$fileName');
}

/// Opens the assets folder in the system file browser.
/// On mobile, shows a dialog with the path since direct folder opening isn't supported.
Future<void> openAssetsFolder(BuildContext context) async {
  final assetsDir = await getAssetsDirectory();
  if (assetsDir == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom files not supported on this platform')),
      );
    }
    return;
  }

  final path = assetsDir.path;

  if (Platform.isWindows) {
    await Process.run('explorer.exe', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  } else {
    // Mobile platforms: show dialog with path
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Assets Folder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your custom files are stored at:'),
              const SizedBox(height: 12),
              SelectableText(
                path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (Platform.isIOS)
                const Text(
                  'Open the Files app → On My iPhone → Head Copy → assets',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              if (Platform.isAndroid)
                const Text(
                  'Use a file manager app to navigate to this folder.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

enum PracticeMode { adaptive, characters, groups, words, qso }

enum WordListType { cwWords, commonWords, callsigns }

WordListType _parseWordListType(String? value) {
  switch (value) {
    case 'common':
      return WordListType.commonWords;
    case 'callsigns':
      return WordListType.callsigns;
    default:
      return WordListType.cwWords;
  }
}

String _wordListTypeToString(WordListType type) {
  switch (type) {
    case WordListType.commonWords:
      return 'common';
    case WordListType.callsigns:
      return 'callsigns';
    case WordListType.cwWords:
      return 'cw';
  }
}

final _kValidTones = [for (var i = 350; i <= 1500; i += 25) i];

class CwTrainerSettings {
  int actualWpm = 20;
  int effectiveWpm = 15;
  EffectiveSpeedMode effectiveMode = EffectiveSpeedMode.farnsworth;
  int kochLearnedCount = 2;
  int frequencyHz = 700;
  int groupSize = 5;
  bool wordsOnlyLearnedLetters = true;
  WordListType wordListType = WordListType.cwWords;
  /// Delay (ms) before showing received characters; playing the next is not delayed.
  int displayDelayMs = 400;
  /// Session length in minutes (0 = unlimited).
  int sessionLengthMinutes = 5;
  /// The learner's own callsign (uppercase, encodable), or '' if unset. Used in
  /// the adaptive Copy curriculum and generated exchanges.
  String callsign = '';

  static Future<CwTrainerSettings> load(SharedPreferences prefs) async {
    final hz = prefs.getInt('frequencyHz') ?? 700;
    return CwTrainerSettings()
      ..actualWpm = prefs.getInt('actualWpm') ?? 20
      ..effectiveWpm = prefs.getInt('effectiveWpm') ?? 15
      ..effectiveMode = prefs.getString('effectiveMode') == 'wordsworth' ? EffectiveSpeedMode.wordsworth : EffectiveSpeedMode.farnsworth
      ..kochLearnedCount = prefs.getInt('kochLearnedCount') ?? 2
      ..frequencyHz = _kValidTones.contains(hz) ? hz : 700
      ..groupSize = prefs.getInt('groupSize') ?? 5
      ..wordsOnlyLearnedLetters = prefs.getBool('wordsOnlyLearnedLetters') ?? true
      ..wordListType = _parseWordListType(prefs.getString('wordListType'))
      ..displayDelayMs = prefs.getInt('displayDelayMs') ?? 400
      ..sessionLengthMinutes = prefs.getInt('sessionLengthMinutes') ?? 5
      ..callsign = prefs.getString('callsign') ?? '';
  }

  static Future<void> save(SharedPreferences prefs, CwTrainerSettings s) async {
    await prefs.setInt('actualWpm', s.actualWpm);
    await prefs.setInt('effectiveWpm', s.effectiveWpm);
    await prefs.setString('effectiveMode', s.effectiveMode == EffectiveSpeedMode.wordsworth ? 'wordsworth' : 'farnsworth');
    await prefs.setInt('kochLearnedCount', s.kochLearnedCount);
    await prefs.setInt('frequencyHz', s.frequencyHz);
    await prefs.setInt('groupSize', s.groupSize);
    await prefs.setBool('wordsOnlyLearnedLetters', s.wordsOnlyLearnedLetters);
    await prefs.setString('wordListType', _wordListTypeToString(s.wordListType));
    await prefs.setInt('displayDelayMs', s.displayDelayMs);
    await prefs.setInt('sessionLengthMinutes', s.sessionLengthMinutes);
    await prefs.setString('callsign', s.callsign);
  }
}

/// Normalizes free-form callsign input: uppercase, trimmed, only chars the
/// Morse engine can send. Returns '' if nothing valid remains.
String normalizeCallsign(String raw) {
  final up = raw.trim().toUpperCase();
  final buf = StringBuffer();
  for (final ch in up.split('')) {
    if (kMorseCode.containsKey(ch)) buf.write(ch);
  }
  return buf.toString();
}

class CwTrainerPage extends StatefulWidget {
  const CwTrainerPage({super.key});

  @override
  State<CwTrainerPage> createState() => _CwTrainerPageState();
}

class _CwTrainerPageState extends State<CwTrainerPage>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final Random _rnd = Random();
  final ScrollController _scrollController = ScrollController();
  CwTrainerSettings _settings = CwTrainerSettings();
  PracticeMode _mode = PracticeMode.adaptive;
  Directory? _storageDir;
  /// Bumped when Copy progress is reset, to force a fresh AdaptivePage (which
  /// otherwise holds in-memory state that would re-save on dispose).
  int _adaptiveEpoch = 0;
  bool _running = false;
  bool _paused = false;
  String _displayText = '';
  StreamSubscription? _completeSub;
  Timer? _sessionTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  List<String> _cwWords = [];
  List<String> _commonWords = [];
  List<String> _callsigns = [];
  List<List<String>> _qsos = [];
  int _currentQsoIndex = -1;
  int _currentQsoLine = 0;
  bool _startingNewQso = false;
  AnimationController? _pauseFlashController;

  @override
  void initState() {
    super.initState();
    _pauseFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await initializeUserAssets();
    final dir = await getAssetsDirectory();
    if (mounted) setState(() => _storageDir = dir);
    _loadPreferences();
    _loadWordLists();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenInfo = prefs.getBool('hasSeenInfo') ?? false;
    if (!hasSeenInfo && mounted) {
      await prefs.setBool('hasSeenInfo', true);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
        );
      }
    }
  }

  void _openInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
    );
  }

  Future<void> _loadWordLists() async {
    final cwText = await loadAssetFile('cw-words.txt');
    final englishText = await loadAssetFile('common-english-words.txt');
    final callsignsText = await loadAssetFile('callsigns.txt');
    final qsoText = await loadAssetFile('qsos.txt');
    if (mounted) {
      setState(() {
        _cwWords = cwText.split('\n').map((w) => w.trim().toUpperCase()).where((w) => w.isNotEmpty).toList();
        _commonWords = englishText.split('\n').map((w) => w.trim().toUpperCase()).where((w) => w.isNotEmpty).toList();
        _callsigns = callsignsText.split('\n').map((w) => w.trim().toUpperCase()).where((w) => w.isNotEmpty).toList();
        _qsos = parseQsoBlocks(qsoText);
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final s = await CwTrainerSettings.load(prefs);
    if (mounted) setState(() => _settings = s);
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    _scrollController.dispose();
    _pauseFlashController?.dispose();
    _player.dispose();
    super.dispose();
  }

  Set<String> get _learned => kochLearnedSet(_settings.kochLearnedCount).toSet();

  String get _buttonLabel {
    if (_settings.sessionLengthMinutes == 0) return 'Stop';
    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;
    return 'Stop ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  List<String> get _filteredWords {
    final source = _settings.wordListType == WordListType.cwWords
        ? _cwWords
        : _settings.wordListType == WordListType.commonWords
            ? _commonWords
            : _callsigns;
    // No filtering by learned letters - show all words
    return source.where((w) => w.split('').every((c) => kMorseCode.containsKey(c))).toList();
  }

  bool get _hasWords {
    return _filteredWords.isNotEmpty;
  }

  String _nextCharacters() {
    final set = _learned;
    if (set.isEmpty) return '';
    return set.elementAt(_rnd.nextInt(set.length));
  }

  String _nextGroup() {
    final list = _learned.toList();
    if (list.isEmpty) return '';
    final maxSize = _settings.groupSize.clamp(2, 10);
    final n = 2 + _rnd.nextInt(maxSize - 1); // Random size from 2 to maxSize
    return List.generate(n, (_) => list[_rnd.nextInt(list.length)]).join();
  }

  String _nextWord() {
    var list = _filteredWords;
    if (list.isEmpty) return '';
    return list[_rnd.nextInt(list.length)];
  }

  String _nextQso() {
    // Fallback to built-in phrases if no QSOs loaded
    if (_qsos.isEmpty) {
      if (kQsoPhrases.isEmpty) return '';
      _startingNewQso = true;
      return kQsoPhrases[_rnd.nextInt(kQsoPhrases.length)];
    }
    // Pick a new random QSO if needed
    if (_currentQsoIndex < 0 || _currentQsoLine >= _qsos[_currentQsoIndex].length) {
      _startingNewQso = _currentQsoIndex >= 0; // True if we just finished a QSO
      _currentQsoIndex = _rnd.nextInt(_qsos.length);
      _currentQsoLine = 0;
    } else {
      _startingNewQso = false;
    }
    // Return the next line of the current QSO
    final line = _qsos[_currentQsoIndex][_currentQsoLine];
    _currentQsoLine++;
    return line;
  }

  String _nextPayload() {
    switch (_mode) {
      case PracticeMode.adaptive:
        return ''; // Adaptive mode runs its own loop (AdaptivePage).
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
    if (!_running || _paused) return;
    final text = _nextPayload();
    final isNewQso = _startingNewQso; // Capture before next call changes it
    if (text.isEmpty) {
      _scheduleNext();
      return;
    }
    final wavPath = await renderMorseWavFile(
      text: text,
      actualWpm: _settings.actualWpm,
      effectiveWpm: _settings.effectiveWpm,
      effectiveMode: _settings.effectiveMode,
      frequencyHz: _settings.frequencyHz.toDouble(),
    );
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!_running) return;
      // Delay only the display of what was just played.
      Future.delayed(Duration(milliseconds: _settings.displayDelayMs), () {
        if (!mounted) return;
        setState(() {
          if (_mode == PracticeMode.qso) {
            if (_displayText.isEmpty) {
              _displayText = text;
            } else if (isNewQso) {
              _displayText = '$_displayText\n\n— — —\n\n$text';
            } else {
              _displayText = '$_displayText\n$text';
            }
          } else {
            _displayText = _displayText.isEmpty ? text : '$_displayText $text';
          }
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
    await _player.play(DeviceFileSource(wavPath));
  }

  void _scheduleNext() {
    if (!_running || _paused) return;
    Duration delay = Duration.zero;
    if (_mode == PracticeMode.words || _mode == PracticeMode.groups) {
      // 7 dits inter-word gap at effective speed
      final ditSeconds = _settings.effectiveWpm > 0 ? 1.2 / _settings.effectiveWpm : 0.06;
      delay = Duration(milliseconds: (7 * ditSeconds * 1000).round());
    } else if (_mode == PracticeMode.qso && _startingNewQso) {
      delay = const Duration(milliseconds: 1500);
    }
    Future.delayed(delay, _playNext);
  }

  Future<void> _togglePause() async {
    if (!_running) return;
    if (_paused) {
      // Resume
      _pauseFlashController?.stop();
      _pauseFlashController?.reset();
      setState(() => _paused = false);
      _playNext();
    } else {
      // Pause
      setState(() => _paused = true);
      _pauseFlashController?.repeat(reverse: true);
      await _player.stop();
      _completeSub?.cancel();
    }
  }

  Future<void> _toggleRun() async {
    if (_running) {
      _pauseFlashController?.stop();
      _pauseFlashController?.reset();
      setState(() {
        _running = false;
        _paused = false;
      });
      await _player.stop();
      _completeSub?.cancel();
      _sessionTimer?.cancel();
      _countdownTimer?.cancel();
      return;
    }
    setState(() {
      _running = true;
      _paused = false;
      _displayText = '';
      _remainingSeconds = _settings.sessionLengthMinutes * 60;
      _currentQsoIndex = -1;
      _currentQsoLine = 0;
      _startingNewQso = false;
    });
    // Start session timer if session length is set
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    if (_settings.sessionLengthMinutes > 0) {
      _sessionTimer = Timer(Duration(minutes: _settings.sessionLengthMinutes), () {
        if (_running && mounted) {
          _toggleRun();
        }
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_running || _paused) return;
        setState(() {
          if (_remainingSeconds > 0) _remainingSeconds--;
        });
      });
    }
    _playNext();
  }

  Future<void> _openSetup() async {
    final s = await Navigator.of(context).push<CwTrainerSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: _settings,
          onResetAdaptive: () {
            AdaptivePageState.suppressNextDisposeFlush = true;
            if (mounted) setState(() => _adaptiveEpoch++);
          },
        ),
      ),
    );
    if (s != null && mounted) {
      final callsignChanged = s.callsign != _settings.callsign;
      final prefs = await SharedPreferences.getInstance();
      await CwTrainerSettings.save(prefs, s);
      setState(() {
        _settings = s;
        // A changed callsign changes the Copy curriculum, so rebuild the page
        // to pick it up. Progress is preserved (no suppressNextDisposeFlush).
        if (callsignChanged) _adaptiveEpoch++;
      });
    }
  }

  String get _modeName {
    switch (_mode) {
      case PracticeMode.adaptive:
        return 'Copy';
      case PracticeMode.characters:
        return 'Letters';
      case PracticeMode.groups:
        return 'Groups';
      case PracticeMode.words:
        return 'Words';
      case PracticeMode.qso:
        return 'QSO';
    }
  }

  Color get _modeColor {
    switch (_mode) {
      case PracticeMode.adaptive:
        return Colors.teal;
      case PracticeMode.characters:
        return Colors.blue;
      case PracticeMode.groups:
        return Colors.orange;
      case PracticeMode.words:
        return Colors.green;
      case PracticeMode.qso:
        return Colors.purple;
    }
  }

  Future<void> _updateKochCount(int count) async {
    setState(() => _settings.kochLearnedCount = count);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kochLearnedCount', count);
  }

  Future<void> _updateGroupSize(int size) async {
    setState(() => _settings.groupSize = size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('groupSize', size);
  }

  Future<void> _updateWordListType(WordListType type) async {
    setState(() => _settings.wordListType = type);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wordListType', _wordListTypeToString(type));
  }

  @override
  Widget build(BuildContext context) {
    final isAdaptive = _mode == PracticeMode.adaptive;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _modeColor,
        foregroundColor: Colors.white,
        // When in a drill, show a back arrow to return to Copy.
        leading: isAdaptive
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Copy',
                onPressed: () => _switchMode(PracticeMode.adaptive),
              ),
        title: Text(_modeName),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), tooltip: 'Help', onPressed: _openInfo),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSetup),
          if (isAdaptive)
            PopupMenuButton<PracticeMode>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Practice drills',
              onSelected: _switchMode,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  enabled: false,
                  child: Text('Practice drills', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                PopupMenuItem(value: PracticeMode.characters, child: Text('Letters')),
                PopupMenuItem(value: PracticeMode.groups, child: Text('Groups')),
                PopupMenuItem(value: PracticeMode.words, child: Text('Words')),
                PopupMenuItem(value: PracticeMode.qso, child: Text('QSO')),
              ],
            ),
        ],
      ),
      body: isAdaptive ? _buildAdaptiveBody() : _buildLegacyBody(),
      // Drills keep a small tab bar to switch between the four legacy modes.
      bottomNavigationBar: isAdaptive
          ? null
          : NavigationBar(
              selectedIndex: _drillIndex(_mode),
              onDestinationSelected: (i) => _switchMode(_drillModes[i]),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.sort_by_alpha), label: 'Letters'),
                NavigationDestination(icon: Icon(Icons.abc), label: 'Groups'),
                NavigationDestination(icon: Icon(Icons.menu_book), label: 'Words'),
                NavigationDestination(icon: Icon(Icons.record_voice_over), label: 'QSO'),
              ],
            ),
    );
  }

  static const List<PracticeMode> _drillModes = [
    PracticeMode.characters,
    PracticeMode.groups,
    PracticeMode.words,
    PracticeMode.qso,
  ];

  int _drillIndex(PracticeMode m) {
    final i = _drillModes.indexOf(m);
    return i < 0 ? 0 : i;
  }

  /// Switches practice mode, stopping any running legacy session first so a
  /// drill's audio doesn't keep playing after you leave it.
  void _switchMode(PracticeMode m) {
    if (_running) {
      _pauseFlashController?.stop();
      _pauseFlashController?.reset();
      _player.stop();
      _completeSub?.cancel();
      _sessionTimer?.cancel();
      _countdownTimer?.cancel();
      _running = false;
      _paused = false;
    }
    setState(() => _mode = m);
  }

  Widget _buildAdaptiveBody() {
    return AdaptivePage(
      key: ValueKey('adaptive-$_adaptiveEpoch'),
      storageDir: _storageDir,
      settings: AdaptiveSettings(
        actualWpm: _settings.actualWpm,
        effectiveWpm: _settings.effectiveWpm,
        effectiveMode: _settings.effectiveMode,
        frequencyHz: _settings.frequencyHz,
        bufferDelayMs: _settings.displayDelayMs,
        sessionLengthMinutes: _settings.sessionLengthMinutes,
        callsign: _settings.callsign,
      ),
    );
  }

  Widget _buildLegacyBody() {
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Effective speed indicator
            Text(
              '${_settings.effectiveWpm} / ${_settings.actualWpm} WPM · ${_settings.effectiveMode == EffectiveSpeedMode.farnsworth ? "Farnsworth" : "Wordsworth"}',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            // Characters slider (only in Letters mode)
            if (_mode == PracticeMode.characters) ...[
              const SizedBox(height: 8),
              Text('Letters (${_settings.kochLearnedCount})', style: Theme.of(context).textTheme.labelLarge),
              Slider(
                value: _settings.kochLearnedCount.toDouble(),
                min: 2,
                max: 40,
                divisions: 38,
                label: '${_settings.kochLearnedCount}',
                onChanged: (v) => _updateKochCount(v.round()),
              ),
            ],
            // Group size slider (only in Groups mode)
            if (_mode == PracticeMode.groups) ...[
              const SizedBox(height: 8),
              Text('Max Group Size (${_settings.groupSize})', style: Theme.of(context).textTheme.labelLarge),
              Slider(
                value: _settings.groupSize.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                label: '${_settings.groupSize}',
                onChanged: (v) => _updateGroupSize(v.round()),
              ),
            ],
            // Word list selector (only in Words mode)
            if (_mode == PracticeMode.words) ...[
              const SizedBox(height: 8),
              SegmentedButton<WordListType>(
                segments: const [
                  ButtonSegment(value: WordListType.cwWords, label: Text('CW')),
                  ButtonSegment(value: WordListType.commonWords, label: Text('Common')),
                  ButtonSegment(value: WordListType.callsigns, label: Text('Callsigns')),
                ],
                selected: {_settings.wordListType},
                onSelectionChanged: (s) => _updateWordListType(s.first),
              ),
            ],
            const SizedBox(height: 12),
            // Display (echo after sent)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Container(
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
                    if (_running)
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Error message
            if (_mode == PracticeMode.words && !_hasWords)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No words available',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // Start / Stop / Pause buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_mode == PracticeMode.words && !_hasWords)
                        ? null
                        : _toggleRun,
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(_running ? _buttonLabel : 'Start'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_running) ...[
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _pauseFlashController!,
                    builder: (context, child) => Opacity(
                      opacity: _paused ? 0.4 + 0.6 * _pauseFlashController!.value : 1.0,
                      child: child,
                    ),
                    child: IconButton.filled(
                      onPressed: _togglePause,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      tooltip: _paused ? 'Resume' : 'Pause',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
  }
}

class SettingsPage extends StatefulWidget {
  final CwTrainerSettings settings;
  final VoidCallback? onResetAdaptive;

  const SettingsPage({super.key, required this.settings, this.onResetAdaptive});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _actualWpm;
  late int _effectiveWpm;
  late EffectiveSpeedMode _effectiveMode;
  late double _pitchSlider;
  late int _displayDelayMs;
  late int _sessionLengthMinutes;
  late TextEditingController _sessionLengthController;
  late TextEditingController _callsignController;

  @override
  void initState() {
    super.initState();
    _actualWpm = widget.settings.actualWpm;
    _effectiveWpm = widget.settings.effectiveWpm;
    _effectiveMode = widget.settings.effectiveMode;
    _pitchSlider = _kValidTones.indexOf(widget.settings.frequencyHz).clamp(0, _kValidTones.length - 1).toDouble();
    _displayDelayMs = widget.settings.displayDelayMs;
    _sessionLengthMinutes = widget.settings.sessionLengthMinutes;
    _sessionLengthController = TextEditingController(text: '$_sessionLengthMinutes');
    _callsignController = TextEditingController(text: widget.settings.callsign);
  }

  @override
  void dispose() {
    _sessionLengthController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(CwTrainerSettings()
      ..actualWpm = _actualWpm
      ..effectiveWpm = _effectiveWpm
      ..effectiveMode = _effectiveMode
      ..kochLearnedCount = widget.settings.kochLearnedCount
      ..frequencyHz = _kValidTones[_pitchSlider.round().clamp(0, _kValidTones.length - 1)]
      ..groupSize = widget.settings.groupSize
      ..wordsOnlyLearnedLetters = widget.settings.wordsOnlyLearnedLetters
      ..wordListType = widget.settings.wordListType
      ..displayDelayMs = _displayDelayMs
      ..sessionLengthMinutes = _sessionLengthMinutes
      ..callsign = normalizeCallsign(_callsignController.text));
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
          title: const Text('Settings'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _save),
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your Callsign', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            TextField(
              controller: _callsignController,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. W1ABC',
                helperText: 'Trained early in Copy mode and used in generated exchanges.',
              ),
            ),
            const SizedBox(height: 16),
            Text('Actual Speed ($_actualWpm WPM)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _actualWpm.toDouble(), min: 5, max: 40, divisions: 35, label: '$_actualWpm', onChanged: (v) => setState(() => _actualWpm = v.round())),
            Text('Effective Speed ($_effectiveWpm WPM)', style: Theme.of(context).textTheme.labelLarge),
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
            Text('Pitch (${_kValidTones[_pitchSlider.round()]} Hz)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _pitchSlider, min: 0, max: (_kValidTones.length - 1).toDouble(), divisions: _kValidTones.length - 1, label: '${_kValidTones[_pitchSlider.round()]}', onChanged: (v) => setState(() => _pitchSlider = v)),
            const SizedBox(height: 8),
            Text('Display Delay ($_displayDelayMs ms)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _displayDelayMs.toDouble(), min: 0, max: 5000, divisions: 50, label: '$_displayDelayMs', onChanged: (v) => setState(() => _displayDelayMs = v.round())),
            const SizedBox(height: 8),
            Text('Session Length ($_sessionLengthMinutes min)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton.filled(
                  onPressed: _sessionLengthMinutes > 0
                      ? () => setState(() {
                            _sessionLengthMinutes--;
                            _sessionLengthController.text = '$_sessionLengthMinutes';
                          })
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sessionLengthController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 5',
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed >= 0) {
                        setState(() => _sessionLengthMinutes = parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => setState(() {
                    _sessionLengthMinutes++;
                    _sessionLengthController.text = '$_sessionLengthMinutes';
                  }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _actualWpm = 20;
                  _effectiveWpm = 15;
                  _effectiveMode = EffectiveSpeedMode.farnsworth;
                  _pitchSlider = _kValidTones.indexOf(700).toDouble();
                  _displayDelayMs = 400;
                  _sessionLengthMinutes = 5;
                  _sessionLengthController.text = '5';
                });
                resetWindowSize();
              },
              child: const Text('Reset to defaults'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => openAssetsFolder(context),
              icon: const Icon(Icons.folder_open),
              label: const Text('Open custom files folder'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset Files'),
                    content: const Text(
                      'This will overwrite your custom files with the default versions. Are you sure?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await resetUserAssets();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Files reset to defaults')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('Reset files to defaults'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset Copy Progress'),
                    content: const Text(
                      'This erases all adaptive Copy-mode progress (learned items, '
                      'accuracy, and session history). This cannot be undone. Are you sure?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await resetAdaptiveProgress();
                  widget.onResetAdaptive?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copy progress reset')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Reset Copy progress'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Lightweight first-launch / help intro: a short summary of the Copy approach
/// and the science behind it, with a link to the full reference guide.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _callsignController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prefill if a callsign was already saved.
    SharedPreferences.getInstance().then((prefs) {
      final existing = prefs.getString('callsign') ?? '';
      if (existing.isNotEmpty && mounted) {
        _callsignController.text = existing;
      }
    });
  }

  @override
  void dispose() {
    _callsignController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final call = normalizeCallsign(_callsignController.text);
    if (call.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('callsign', call);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Head Copy CW Trainer')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Copy: a faster way to learn CW',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    'Press Start, listen, then type what you heard — no paper, no peeking. '
                    'The app adapts to you and grows your skill automatically.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _point(
                    theme,
                    icon: Icons.radio,
                    title: 'Real contacts, from day one',
                    body:
                        'You train on the words, prosigns, and phrases you actually hear on '
                        'the air — CQ, DE, 73, UR RST 599, HW CPY? — not endless random letters.',
                  ),
                  _point(
                    theme,
                    icon: Icons.hourglass_bottom,
                    title: 'A pause that builds head copy',
                    body:
                        'A short delay before you answer trains you to hold the sound in your '
                        'head and "copy behind," instead of scribbling letter by letter. It also '
                        'times how fast you recognize each item, so you build instant recognition — '
                        'not slow decoding.',
                  ),
                  _point(
                    theme,
                    icon: Icons.auto_stories,
                    title: 'Whole words right away',
                    body:
                        'Instead of drilling single characters for weeks, you start hearing short '
                        'words and phrases as single sound-shapes — the way skilled operators '
                        'actually copy. Spaced repetition brings back what you miss and moves past '
                        'what you know.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The science: meaningful chunks are learned and recalled far better than '
                    'random strings, expert copy is whole-word recognition rather than letter '
                    'decoding, and gating on recognition speed (not just accuracy) is what breaks '
                    'through the classic plateau.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 24),
                  Text('Your callsign (optional)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    'Your own callsign is the first thing you copy on the air, so Copy '
                    'trains it early and mixes it into realistic exchanges. You can add or '
                    'change it later in Settings.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _callsignController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. W1ABC',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const InfoPage()),
                      ),
                      icon: const Icon(Icons.menu_book),
                      label: const Text('Full guide & classic Koch modes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _finish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get Started'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _point(ThemeData theme,
      {required IconData icon, required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  String _helpContent = '';

  @override
  void initState() {
    super.initState();
    _loadHelp();
  }

  Future<void> _loadHelp() async {
    final content = await loadAssetFile('HELP.md');
    if (mounted) {
      setState(() => _helpContent = content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Head Copy CW Trainer'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _helpContent.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Markdown(
                    data: _helpContent,
                    padding: const EdgeInsets.all(24),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get Started'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
