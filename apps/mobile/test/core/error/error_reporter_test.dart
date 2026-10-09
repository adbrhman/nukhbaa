/// The app's side of the error log (migration 0087): what is reported,
/// what is not, the code the player sees, and reports kept while offline.
library;

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/error/error_presenter.dart';
import 'package:mobile/core/error/error_reporter.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/ui/app_error_state.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

final class _Server {
  final List<ClientErrorReportDto> received = [];
  bool offline = false;

  Future<Result<ClientErrorReportAckDto>> send(
    ClientErrorReportDto report,
  ) async {
    if (offline) {
      return const Result.err(
        AppError.transient('api_client.network_unreachable', 'offline'),
      );
    }
    received.add(report);
    return const Result.ok(ClientErrorReportAckDto(problemCode: 'XXXX'));
  }
}

ClientErrorReporter _reporter(_Server server, MemoryPendingErrorStore store) =>
    ClientErrorReporter(
      send: server.send,
      build: 'abc1234',
      store: store,
      installId: () async => 'install-1',
      deviceSummary: () async =>
          const DeviceSummary(device: 'samsung SM-A105F', os: 'Android 11'),
      source: 'android',
    );

ApiFailure _failure(AppError error, {int? status}) => ApiFailure(
  method: 'GET',
  path: '/seasons/6bf8134c-3eed-46ce-a0dc-e3dc5d4c57c2/fixtures',
  error: error,
  statusCode: status,
  requestId: '0123456789abcdef',
);

const AppError _serverDown = AppError(
  kind: ErrorKind.transient,
  code: apiErrorUnexpectedStatus,
  message: 'The server returned an unexpected status (502).',
);

void main() {
  group('ErrorPresenter', () {
    test('an unexpected failure shows its problem code', () {
      final String message = ErrorPresenter.message(_serverDown);
      final String? code = ErrorPresenter.problemCode(_serverDown);

      expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}$')));
      expect(message, contains('${ErrorPresenter.problemCodeLabel} $code'));
      expect(ErrorPresenter.problemCodeIn(message), code);
    });

    test('the server code wins when the server logged the failure', () {
      const AppError logged = AppError(
        kind: ErrorKind.transient,
        code: 'db.timeout',
        message: 'timed out',
        problemCode: 'S7L9',
      );

      expect(ErrorPresenter.message(logged), contains('S7L9'));
      expect(ErrorPresenter.isReportable(logged), isFalse);
    });

    test('an expected refusal or being offline shows no code', () {
      const List<AppError> expected = [
        AppError.authorization('auth.invalid_credentials', 'Wrong password'),
        AppError.invariant('prediction.fixture_locked', 'Kicked off'),
        AppError.validation('identity.display_name_taken', 'Taken'),
        AppError.transient('api_client.network_unreachable', 'Offline'),
      ];
      for (final AppError error in expected) {
        expect(ErrorPresenter.problemCode(error), isNull, reason: error.code);
        expect(
          ErrorPresenter.message(error),
          isNot(contains(ErrorPresenter.problemCodeLabel)),
        );
      }
    });

    test('no stack or cause ever reaches the player', () {
      final AppError withCause = AppError(
        kind: ErrorKind.transient,
        code: apiErrorTimeout,
        message: 'The server took too long to respond.',
        cause: StateError('#0 secret frame (package:mobile/x.dart:1:1)'),
      );

      expect(ErrorPresenter.message(withCause), isNot(contains('#0')));
    });
  });

  group('ClientErrorReporter', () {
    test('an API failure the server could not answer is reported under the '
        'code the player saw', () async {
      final _Server server = _Server();
      final MemoryPendingErrorStore store = MemoryPendingErrorStore();
      final ClientErrorReporter reporter = _reporter(server, store);

      reporter.reportApiFailure(_failure(_serverDown, status: 502));
      await reporter.drain();

      final ClientErrorReportDto sent = server.received.single;
      expect(sent.errorType, 'AppError');
      expect(sent.errorCode, apiErrorUnexpectedStatus);
      expect(sent.route, 'GET /seasons/:id/fixtures');
      expect(sent.requestId, '0123456789abcdef');
      expect(sent.installId, 'install-1');
      expect(sent.device, 'samsung SM-A105F');
      expect(store.reports, isEmpty);
      expect(
        ErrorFingerprint.of(
          source: 'android',
          errorType: sent.errorType,
          errorCode: sent.errorCode,
        ).problemCode,
        ErrorPresenter.problemCode(_serverDown),
      );
    });

    test('expected failures are not reported', () async {
      final _Server server = _Server();
      final ClientErrorReporter reporter = _reporter(
        server,
        MemoryPendingErrorStore(),
      );

      reporter.reportApiFailure(
        _failure(
          const AppError.authorization('auth.invalid_credentials', 'x'),
          status: 401,
        ),
      );
      reporter.reportApiFailure(
        _failure(
          const AppError.transient('api_client.network_unreachable', 'x'),
        ),
      );
      reporter.reportApiFailure(
        _failure(
          const AppError(
            kind: ErrorKind.transient,
            code: 'db.timeout',
            message: 'x',
            problemCode: 'S7L9',
          ),
          status: 503,
        ),
      );
      await reporter.drain();

      expect(server.received, isEmpty);
    });

    test('a timeout of a background report is not reported, and leaves '
        'the quota to a timeout the player saw', () async {
      final _Server server = _Server();
      final ClientErrorReporter reporter = _reporter(
        server,
        MemoryPendingErrorStore(),
      );
      const AppError timeout = AppError(
        kind: ErrorKind.transient,
        code: apiErrorTimeout,
        message: 'The server took too long to respond. Please try again.',
      );

      // The tab is hidden: the frame and screen reports time out, three of
      // them, as many as one problem code may report in a run.
      for (final String path in <String>[
        '/me/frame-report',
        '/me/screen-views',
        '/me/frame-report',
      ]) {
        reporter.reportApiFailure(
          ApiFailure(method: 'POST', path: path, error: timeout),
        );
      }
      // Then a screen read times out.
      reporter.reportApiFailure(_failure(timeout));
      // A background report that the server answered badly is still news.
      reporter.reportApiFailure(
        ApiFailure(
          method: 'POST',
          path: '/me/frame-report',
          error: _serverDown,
          statusCode: 502,
        ),
      );
      await reporter.drain();

      expect(server.received.map((ClientErrorReportDto r) => r.route), <String>[
        'GET /seasons/:id/fixtures',
        'POST /me/frame-report',
      ]);
      expect(server.received.first.errorCode, apiErrorTimeout);
      expect(server.received.last.errorCode, apiErrorUnexpectedStatus);
    });

    test('a timeout while the app is away, or just back, is not reported; '
        'one in the foreground is', () async {
      final _Server server = _Server();
      DateTime now = DateTime.utc(2026, 10, 9, 17, 37);
      final ClientErrorReporter reporter = ClientErrorReporter(
        send: server.send,
        build: 'abc1234',
        store: MemoryPendingErrorStore(),
        installId: () async => 'install-1',
        deviceSummary: () async =>
            const DeviceSummary(device: 'samsung SM-N950U', os: 'Android 9'),
        source: 'android',
        now: () => now,
      );
      const AppError timeout = AppError(
        kind: ErrorKind.transient,
        code: apiErrorTimeout,
        message: 'The server took too long to respond. Please try again.',
      );

      // The phone goes to the background with the feed read still out.
      reporter.noteLifecycle(AppLifecycleState.inactive);
      reporter.noteLifecycle(AppLifecycleState.hidden);
      reporter.noteLifecycle(AppLifecycleState.paused);
      reporter.reportApiFailure(_failure(timeout));
      // A server failure is news even then.
      reporter.reportApiFailure(_failure(_serverDown, status: 502));

      // Back five minutes later: the read's timer fires on the way in.
      now = now.add(const Duration(minutes: 5));
      reporter.noteLifecycle(AppLifecycleState.resumed);
      now = now.add(const Duration(seconds: 3));
      reporter.reportApiFailure(_failure(timeout));

      // Half a minute in the foreground: a timeout now is the server's.
      now = now.add(const Duration(seconds: 30));
      reporter.reportApiFailure(_failure(timeout));
      await reporter.drain();

      expect(
        server.received.map((ClientErrorReportDto r) => r.errorCode),
        <String>[apiErrorUnexpectedStatus, apiErrorTimeout],
      );
    });

    test('an exception is reported with its stack and the same code the '
        'app shows', () async {
      final _Server server = _Server();
      final ClientErrorReporter reporter = _reporter(
        server,
        MemoryPendingErrorStore(),
      );
      final StackTrace stack = StackTrace.fromString(
        '#0      FixtureCard.build '
        '(package:mobile/features/fixtures/card.dart:88:7)',
      );

      final String code = reporter.reportException(
        StateError('no element'),
        stack,
        where: 'building FixtureCard',
        fatal: true,
      );
      await reporter.drain();

      final ClientErrorReportDto sent = server.received.single;
      expect(sent.errorType, 'StateError');
      expect(sent.fatal, isTrue);
      expect(sent.route, 'building FixtureCard');
      expect(
        ErrorFingerprint.of(
          source: 'android',
          errorType: 'StateError',
          stack: sent.stack,
        ).problemCode,
        code,
      );
    });

    test('offline, a report is kept and sent on the next flush', () async {
      final _Server server = _Server()..offline = true;
      final MemoryPendingErrorStore store = MemoryPendingErrorStore();
      final ClientErrorReporter reporter = _reporter(server, store);

      reporter.reportException(StateError('a'), StackTrace.empty);
      await reporter.drain();
      expect(server.received, isEmpty);
      expect(store.reports, hasLength(1));
      final Map<String, Object?> kept =
          jsonDecode(store.reports.single) as Map<String, Object?>;
      expect(kept['error_type'], 'StateError');

      server.offline = false;
      await _reporter(server, store).flush();

      expect(server.received, hasLength(1));
      expect(store.reports, isEmpty);
    });

    test('at most a few reports of one error, and a capped queue', () async {
      final _Server server = _Server()..offline = true;
      final MemoryPendingErrorStore store = MemoryPendingErrorStore();
      final ClientErrorReporter reporter = _reporter(server, store);

      for (var i = 0; i < 10; i++) {
        reporter.reportException(StateError('same'), StackTrace.empty);
      }
      await reporter.drain();
      expect(store.reports, hasLength(ClientErrorReporter.maxPerError));

      for (var i = 0; i < 40; i++) {
        reporter.reportException(ArgumentError('n$i'), StackTrace.empty);
        reporter.reportException(RangeError('n$i'), StackTrace.empty);
        reporter.reportException(FormatException('n$i'), StackTrace.empty);
      }
      await reporter.drain();
      expect(
        store.reports.length,
        lessThanOrEqualTo(ClientErrorReporter.maxPending),
      );
    });
  });

  testWidgets('the error state offers to copy the problem code', (
    tester,
  ) async {
    final String message = ErrorPresenter.message(_serverDown);
    final String code = ErrorPresenter.problemCode(_serverDown)!;
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: AppErrorState(message: message)),
      ),
    );
    await tester.tap(find.byKey(const Key('error.copyProblemCode')));
    await tester.pump();

    final MethodCall copy = calls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect((copy.arguments as Map<Object?, Object?>)['text'], code);

    // The copy is confirmed on screen (UI-30).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
    expect(find.text(ar.problemCodeCopied), findsOneWidget);
  });

  testWidgets('an ordinary message has no copy button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: AppErrorState(message: 'حدث خطأ ما')),
      ),
    );

    expect(find.byKey(const Key('error.copyProblemCode')), findsNothing);
  });
}
