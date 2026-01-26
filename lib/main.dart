import 'package:flutter/material.dart';

import 'cw_trainer_page.dart';

void main() {
  runApp(const CwTrainerApp());
}

class CwTrainerApp extends StatelessWidget {
  const CwTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CW Trainer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CwTrainerPage(),
    );
  }
}
