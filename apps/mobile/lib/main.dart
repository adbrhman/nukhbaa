library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/design/app_spacing.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android only. There is no Firebase configuration for the web build,
  // and initialising without one throws before the first frame -- which
  // would take down the GitHub Pages build with it.
  if (!kIsWeb) {
    await Firebase.initializeApp();
  }

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on StateError catch (e) {
    runApp(_ConfigErrorApp(message: e.message));
    return;
  }
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const NukhbaApp(),
    ),
  );
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Configuration error\n\n$message',
            key: const Key('app.configError'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
