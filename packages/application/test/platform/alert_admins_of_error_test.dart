import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 3, 12);
}

/// Claims like `ops.claim_error_alert`: the [reason] once, then null for
/// the rest of the hour.
final class _Alerts implements ErrorAlertRepository {
  _Alerts(this.reason);

  final String? reason;
  final List<({int groupId, bool isNew, bool reopened})> claims = [];

  @override
  Future<Result<String?>> claim({
    required int groupId,
    required bool isNew,
    required bool reopened,
    required DateTime at,
  }) async {
    claims.add((groupId: groupId, isNew: isNew, reopened: reopened));
    return Result.ok(claims.length == 1 ? reason : null);
  }
}

final class _Admins implements AdminPushTargetReader {
  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      const Result.ok(['admin-token']);
}

final class _Sender implements PushSender {
  final List<({List<String> tokens, String title, String body})> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sent.add((tokens: tokens, title: title, body: body));
    return const Result.ok([]);
  }
}

final class _Log implements ErrorLogRepository {
  int count = 0;

  @override
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence) async {
    count++;
    return Result.ok(
      RecordedError(
        groupId: 7,
        occurrences: count,
        status: 'new',
        severity: occurrence.severity.name,
        usersAffected: 0,
        isNew: count == 1,
        reopened: false,
      ),
    );
  }
}

ErrorReport _critical() => const ErrorReport(
  source: 'server',
  errorType: 'StateError',
  message: 'Bad state: password=hunter2',
  severity: ErrorSeverity.critical,
  build: 'abc1234',
  route: 'job rescore',
);

void main() {
  test('a new critical error alerts the admins once within the hour, '
      'through the real entry point', () async {
    final alerts = _Alerts('new_critical');
    final sender = _Sender();
    final record = RecordError(
      errors: _Log(),
      clock: _Clock(),
      alerts: AlertAdminsOfError(
        alerts: alerts,
        targets: _Admins(),
        sender: sender,
        clock: _Clock(),
      ),
    );

    await record(_critical());
    await record(_critical());

    expect(alerts.claims, hasLength(2));
    expect(alerts.claims.first.isNew, isTrue);
    expect(sender.sent, hasLength(1), reason: 'one alert in the hour');
    final push = sender.sent.single;
    expect(push.tokens, ['admin-token']);
    expect(push.title, AlertAdminsOfError.titleFor('new_critical'));
    expect(push.body, contains('server'));
    expect(push.body, isNot(contains('hunter2')));
  });

  test('nothing worth telling sends nothing', () async {
    final sender = _Sender();
    final record = RecordError(
      errors: _Log(),
      clock: _Clock(),
      alerts: AlertAdminsOfError(
        alerts: _Alerts(null),
        targets: _Admins(),
        sender: sender,
        clock: _Clock(),
      ),
    );

    final result = await record(_critical());

    expect(result.isOk, isTrue);
    expect(sender.sent, isEmpty);
  });

  test('a failing alert never fails the record', () async {
    final record = RecordError(
      errors: _Log(),
      clock: _Clock(),
      alerts: AlertAdminsOfError(
        alerts: _FailingAlerts(),
        targets: _Admins(),
        sender: _Sender(),
        clock: _Clock(),
      ),
    );

    final result = await record(_critical());

    expect(result.isOk, isTrue);
  });

  group('an app report alerts only from a signed-in player (M-19)', () {
    ErrorReport appReport({String? userId}) => ErrorReport(
      source: 'android',
      errorType: 'StateError',
      message: 'Bad state: no element',
      severity: ErrorSeverity.high,
      build: 'made-up-build-1',
      userId: userId,
    );

    test('nobody signed in: kept, and no admin is told', () async {
      final alerts = _Alerts('new_in_release');
      final sender = _Sender();
      final log = _Log();
      final record = RecordError(
        errors: log,
        clock: _Clock(),
        alerts: AlertAdminsOfError(
          alerts: alerts,
          targets: _Admins(),
          sender: sender,
          clock: _Clock(),
        ),
      );

      final result = await record(appReport());

      expect(result.isOk, isTrue);
      expect(log.count, 1);
      expect(alerts.claims, isEmpty);
      expect(sender.sent, isEmpty);
    });

    test('a signed-in player: the admins are told', () async {
      final alerts = _Alerts('new_in_release');
      final sender = _Sender();
      final record = RecordError(
        errors: _Log(),
        clock: _Clock(),
        alerts: AlertAdminsOfError(
          alerts: alerts,
          targets: _Admins(),
          sender: sender,
          clock: _Clock(),
        ),
      );

      await record(appReport(userId: '11111111-2222-3333-4444-555555555555'));

      expect(alerts.claims, hasLength(1));
      expect(sender.sent, hasLength(1));
    });
  });

  test('every reason has an Arabic title', () {
    for (final reason in [
      'reopened',
      'new_critical',
      'new_in_release',
      'hourly_spike',
    ]) {
      expect(AlertAdminsOfError.titleFor(reason), startsWith('سجل الأخطاء:'));
    }
  });
}

final class _FailingAlerts implements ErrorAlertRepository {
  @override
  Future<Result<String?>> claim({
    required int groupId,
    required bool isNew,
    required bool reopened,
    required DateTime at,
  }) async => const Result.err(AppError.transient('db.down', 'down'));
}
