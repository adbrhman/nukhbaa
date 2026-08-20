library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/session_gate.dart';
import 'features/update/update_gate.dart';
import 'l10n/app_localizations.dart';

class NukhbaApp extends ConsumerWidget {
  const NukhbaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: 'Nukhba',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final MediaQueryData mq = MediaQuery.of(context);
        final TextScaler capped = mq.textScaler.clamp(
          minScaleFactor: 1,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: capped),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const UpdateGate(child: SessionGate()),
    );
  }
}
