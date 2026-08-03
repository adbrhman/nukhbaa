library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/design/app_spacing.dart';
import 'core/providers.dart';

void main() {
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
