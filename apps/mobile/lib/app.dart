library;

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/session_gate.dart';

class NukhbaApp extends StatelessWidget {
  const NukhbaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nukhba',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SessionGate(),
    );
  }
}
