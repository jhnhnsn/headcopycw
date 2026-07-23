import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart' show resetWindowSize;
import 'morse_data.dart';
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



final _kValidTones = [for (var i = 350; i <= 1500; i += 25) i];

class CwTrainerSettings {
  int frequencyHz = 700;
  /// Session length in minutes (0 = unlimited).
  int sessionLengthMinutes = 5;
  /// The learner's own callsign (uppercase, encodable), or '' if unset. Used in
  /// the adaptive Copy curriculum and generated exchanges.
  String callsign = '';
  /// Copy on paper: no typing during the session (hear → write → Done), then
  /// enter everything at the end to score.
  bool paperMode = false;

  static Future<CwTrainerSettings> load(SharedPreferences prefs) async {
    final hz = prefs.getInt('frequencyHz') ?? 700;
    return CwTrainerSettings()
      ..frequencyHz = _kValidTones.contains(hz) ? hz : 700
      ..sessionLengthMinutes = prefs.getInt('sessionLengthMinutes') ?? 5
      ..callsign = prefs.getString('callsign') ?? ''
      ..paperMode = prefs.getBool('paperMode') ?? false;
  }

  static Future<void> save(SharedPreferences prefs, CwTrainerSettings s) async {
    await prefs.setInt('frequencyHz', s.frequencyHz);
    await prefs.setInt('sessionLengthMinutes', s.sessionLengthMinutes);
    await prefs.setString('callsign', s.callsign);
    await prefs.setBool('paperMode', s.paperMode);
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

class _CwTrainerPageState extends State<CwTrainerPage> {
  CwTrainerSettings _settings = CwTrainerSettings();
  Directory? _storageDir;
  /// Bumped when Copy progress is reset (or callsign changes), to force a fresh
  /// AdaptivePage (which otherwise holds in-memory state that re-saves on dispose).
  int _adaptiveEpoch = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await initializeUserAssets();
    final dir = await getAssetsDirectory();
    if (mounted) setState(() => _storageDir = dir);
    _loadPreferences();
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

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final s = await CwTrainerSettings.load(prefs);
    if (mounted) setState(() => _settings = s);
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
      // A changed callsign or paper-mode toggle changes the Copy loop, so
      // rebuild the page to pick it up. Progress is preserved.
      final rebuild = s.callsign != _settings.callsign ||
          s.paperMode != _settings.paperMode;
      final prefs = await SharedPreferences.getInstance();
      await CwTrainerSettings.save(prefs, s);
      setState(() {
        _settings = s;
        if (rebuild) _adaptiveEpoch++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: const Text('Copy'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), tooltip: 'Help', onPressed: _openInfo),
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: _openSetup),
        ],
      ),
      body: AdaptivePage(
        key: ValueKey('adaptive-$_adaptiveEpoch'),
        storageDir: _storageDir,
        settings: AdaptiveSettings(
          frequencyHz: _settings.frequencyHz,
          sessionLengthMinutes: _settings.sessionLengthMinutes,
          callsign: _settings.callsign,
          paperMode: _settings.paperMode,
        ),
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
  late double _pitchSlider;
  late int _sessionLengthMinutes;
  late bool _paperMode;
  late TextEditingController _sessionLengthController;
  late TextEditingController _callsignController;

  @override
  void initState() {
    super.initState();
    _pitchSlider = _kValidTones.indexOf(widget.settings.frequencyHz).clamp(0, _kValidTones.length - 1).toDouble();
    _sessionLengthMinutes = widget.settings.sessionLengthMinutes;
    _paperMode = widget.settings.paperMode;
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
      ..frequencyHz = _kValidTones[_pitchSlider.round().clamp(0, _kValidTones.length - 1)]
      ..sessionLengthMinutes = _sessionLengthMinutes
      ..callsign = normalizeCallsign(_callsignController.text)
      ..paperMode = _paperMode);
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
            // Difficulty is fully app-controlled — speed and the copy-behind
            // buffer both adapt to you. Shown here read-only.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_graph, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Difficulty adapts automatically — Copy starts gently and, as your '
                      'recognition gets fast and accurate, speeds you up and adds a '
                      '"copy behind" delay to build head-copy. Nothing to set.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Pitch (${_kValidTones[_pitchSlider.round()]} Hz)', style: Theme.of(context).textTheme.labelLarge),
            Slider(value: _pitchSlider, min: 0, max: (_kValidTones.length - 1).toDouble(), divisions: _kValidTones.length - 1, label: '${_kValidTones[_pitchSlider.round()]}', onChanged: (v) => setState(() => _pitchSlider = v)),
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
            const SizedBox(height: 8),

            // Copy on paper toggle.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _paperMode,
              onChanged: (v) => setState(() => _paperMode = v),
              title: const Text('Copy on paper'),
              subtitle: Text(
                'No typing during the session — hear it, write it, then enter '
                'everything at the end to score.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),

            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _pitchSlider = _kValidTones.indexOf(700).toDouble();
                  _sessionLengthMinutes = 5;
                  _sessionLengthController.text = '5';
                  _paperMode = false;
                });
                resetWindowSize();
              },
              child: const Text('Reset to defaults'),
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
                    icon: Icons.speed,
                    title: 'It adapts to you',
                    body:
                        'The app times how fast you recognize each item and only moves on when '
                        'you\'re both accurate and quick. As you improve it speeds you up — and '
                        'later adds a "copy behind" delay to build true head copy. You never set '
                        'a difficulty.',
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
                      label: const Text('Full guide'),
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
