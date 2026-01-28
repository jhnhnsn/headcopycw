import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'cw_trainer_page.dart';

const double kDefaultWindowWidth = 400;
const double kDefaultWindowHeight = 800;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    // Load saved window size
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('windowWidth') ?? kDefaultWindowWidth;
    final height = prefs.getDouble('windowHeight') ?? kDefaultWindowHeight;

    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      minimumSize: const Size(300, 400),
      center: true,
      title: 'Head Copy',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const CwTrainerApp());
}

class CwTrainerApp extends StatefulWidget {
  const CwTrainerApp({super.key});

  @override
  State<CwTrainerApp> createState() => _CwTrainerAppState();
}

class _CwTrainerAppState extends State<CwTrainerApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResized() async {
    // Save window size when resized
    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('windowWidth', size.width);
    await prefs.setDouble('windowHeight', size.height);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Head Copy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CwTrainerPage(),
    );
  }
}

/// Resets the window size to default. Call from settings reset.
Future<void> resetWindowSize() async {
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('windowWidth');
    await prefs.remove('windowHeight');
    await windowManager.setSize(const Size(kDefaultWindowWidth, kDefaultWindowHeight));
  }
}
