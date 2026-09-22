import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/error/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const String _dsn = 'https://key@o1.ingest.de.sentry.io/1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a build carrying a DSN reports', () {
    expect(crashReportingEnabled(''), isFalse);
    expect(crashReportingEnabled('   '), isFalse);
    expect(crashReportingEnabled(_dsn), isTrue);
  });

  test('the policy sends errors only, with no personal data', () {
    final SentryFlutterOptions options = SentryFlutterOptions();
    configureCrashReporting(options, dsn: ' $_dsn ', buildSha: 'abc1234');
    expect(options.dsn, _dsn);
    expect(options.environment, 'production');
    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.tracesSampleRate, isNull);
    expect(options.release, 'nukhbaa@abc1234');
  });

  test('a build without a commit sha keeps the SDK default release', () {
    final SentryFlutterOptions options = SentryFlutterOptions();
    final String? before = options.release;
    configureCrashReporting(options, dsn: _dsn, buildSha: '');
    expect(options.release, before);
  });
}
