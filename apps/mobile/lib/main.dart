library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'app.dart';
import 'core/auth/install_id.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/error/crash_reporting.dart';
import 'core/error/error_reporter.dart';
import 'core/network/http_client.dart';
import 'core/design/app_spacing.dart';
import 'core/providers.dart';
import 'core/session/session_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash reporting wraps everything that follows, so a failure while
  // starting Firebase or reading the build configuration is reported too.
  // A build without NUKHBA_SENTRY_DSN (local runs, tests) starts as before.
  if (!crashReportingEnabled(sentryDsn)) {
    await _startApp();
    return;
  }
  if (kIsWeb) {
    // On the web, SentryFlutter.init waits for its script from
    // browser.sentry-cdn.com before it calls appRunner, and some networks
    // block that host: the page stayed blank. The app starts first here,
    // and reporting follows whenever (and if) the script arrives.
    await _startApp();
    unawaited(
      SentryFlutter.init(
        (options) => configureCrashReporting(options, dsn: sentryDsn),
      ),
    );
    return;
  }
  await SentryFlutter.init(
    (options) => configureCrashReporting(options, dsn: sentryDsn),
    appRunner: _startApp,
  );
}

Future<void> _startApp() async {
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
  // Unexpected errors go to the admin dashboard's error log (migration
  // 0087) over a transport of their own, so a report never waits on, or
  // feeds back into, the app's own calls. A signed-in player's token names
  // them; before sign-in the report goes anonymously.
  installErrorReporting(
    ClientErrorReporter(
      send: AppApi(
        ApiTransport(
          baseUri: config.apiBaseUrl,
          httpClient: createHttpClient(),
          tokenProvider: SecureTokenStore(const FlutterSecureStorage()).read,
        ),
      ).reportError,
      build: const String.fromEnvironment('NUKHBA_BUILD_SHA'),
      store: const SecurePendingErrorStore(),
      installId: kIsWeb ? null : SecureInstallIdStore().read,
    ),
  );
  // SessionScope hosts the root ProviderScope and replaces it on sign-out,
  // so one account's cached reads never reach the next account.
  runApp(
    SessionScope(
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
