/// Crash reporting (GitHub Issue #1): which builds report, and what they send.
///
/// Sentry's Flutter SDK captures uncaught Dart errors and, through the
/// Android SDK it bundles, native Java/Kotlin/NDK crashes as well -- so no
/// second crash reporter runs alongside it. Only errors are sent: tracing,
/// profiling and session replay stay off, which keeps the free plan's
/// monthly quota for errors.
library;

import 'package:sentry_flutter/sentry_flutter.dart';

/// Injected by the release builds (CI, from the `NUKHBA_SENTRY_DSN`
/// repository variable). Empty in local and test builds, which therefore
/// report nothing.
const String sentryDsn = String.fromEnvironment('NUKHBA_SENTRY_DSN');

/// The short commit sha CI already injects for the OTA check.
const String _buildSha = String.fromEnvironment('NUKHBA_BUILD_SHA');

/// Whether a build carrying [dsn] reports crashes at all.
bool crashReportingEnabled(String dsn) => dsn.trim().isNotEmpty;

/// Applies the app's reporting policy to [options].
///
/// No personal data leaves the device: Sentry's own switch for IP addresses
/// and request details stays off, and no screenshot is attached. The release
/// is the build's commit, so an error names the exact build that raised it.
void configureCrashReporting(
  SentryFlutterOptions options, {
  required String dsn,
  String buildSha = _buildSha,
}) {
  options
    ..dsn = dsn.trim()
    ..environment = 'production'
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..tracesSampleRate = null;
  if (buildSha.isNotEmpty) {
    options.release = 'nukhbaa@$buildSha';
  }
}
