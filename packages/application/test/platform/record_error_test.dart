import 'dart:convert';

import 'package:application/application.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 3, 12);
}

final class _MemoryErrorLog implements ErrorLogRepository {
  final List<ErrorOccurrence> kept = [];

  @override
  Future<Result<RecordedError>> record(ErrorOccurrence occurrence) async {
    kept.add(occurrence);
    return Result.ok(
      RecordedError(
        groupId: 1,
        occurrences: kept.length,
        status: 'new',
        severity: occurrence.severity.name,
        usersAffected: 1,
        isNew: kept.length == 1,
        reopened: false,
      ),
    );
  }
}

// One of each secret the error log must never keep.
const _secrets = <String, String>{
  'password': 'password=hunter2',
  'authorization header': 'Authorization: Bearer abc.def.ghi',
  'access token (jwt)':
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJlLXZhbHVl',
  'refresh token': 'refresh_token=8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c',
  'api key': 'api_key=AIzaSyD-1234567890abcdefghijklmnopq',
  'install id': 'install_id=phone-a-install-0001',
  'email': 'ali.saleh@example.com',
  'database url': 'postgres://postgres.ref:S3cretPw@pooler:6543/postgres',
  'fcm token': 'fX9k2LmQ7pR3sT8vW1yZ4aB6cD0eF5gH2jK9mN3pQ7rS1tU',
};

// The part of each secret that must not survive.
const _secretValues = <String, String>{
  'password': 'hunter2',
  'authorization header': 'abc.def.ghi',
  'access token (jwt)': 'eyJhbGciOiJIUzI1NiJ9',
  'refresh token': '8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c',
  'api key': 'AIzaSyD',
  'install id': 'phone-a-install-0001',
  'email': 'ali.saleh@example.com',
  'database url': 'S3cretPw',
  'fcm token': 'fX9k2LmQ7pR3sT8vW1yZ4aB6cD0eF5gH2jK9mN3pQ7rS1tU',
};

ErrorReport _report({
  String source = 'server',
  String message = 'Bad state: no element',
  String? stack,
  String build = 'abc1234',
  String? requestId = '0123456789abcdef0123456789abcdef',
  String? userId = _user,
  Map<String, Object?>? input,
}) => ErrorReport(
  source: source,
  errorType: 'StateError',
  errorCode: 'server.unexpected',
  message: message,
  stack: stack,
  route: 'GET /seasons/:id',
  severity: ErrorSeverity.high,
  build: build,
  userId: userId,
  requestId: requestId,
  requestInput: input,
);

void main() {
  late _MemoryErrorLog log;
  late RecordError record;

  setUp(() {
    log = _MemoryErrorLog();
    record = RecordError(errors: log, clock: const _FixedClock());
  });

  group('redaction', () {
    for (final entry in _secrets.entries) {
      test('removes the ${entry.key} from message, stack and input', () async {
        final secret = entry.value;
        final result = await record(
          _report(
            message: 'failed with $secret here',
            stack: '#0      onRequest (file:///app/routes/x.dart:1:1) $secret',
            input: {
              'query': {'q': 'look $secret'},
            },
          ),
        );

        expect(result.isOk, isTrue);
        final kept = log.kept.single;
        final leaked = _secretValues[entry.key]!;
        expect(kept.message, isNot(contains(leaked)));
        expect(kept.message, contains('failed with'));
        expect(kept.stack, isNot(contains(leaked)));
        expect(kept.requestInputJson, isNot(contains(leaked)));
      });
    }

    test('a secret key hides its whole value, at any depth', () async {
      await record(
        _report(
          input: {
            'password': 'x',
            'page': 2,
            'nested': {'refresh_token': 'y', 'note': 'mail me at a@b.co'},
          },
        ),
      );

      final input =
          jsonDecode(log.kept.single.requestInputJson!) as Map<String, Object?>;
      expect(input['password'], ErrorRedaction.mask);
      expect(input['page'], 2);
      final nested = input['nested']! as Map<String, Object?>;
      expect(nested['refresh_token'], ErrorRedaction.mask);
      expect(nested['note'], 'mail me at ${ErrorRedaction.emailMask}');
    });

    test('ordinary text is kept as it was', () async {
      await record(_report(message: 'Bad state: no element in round 3'));

      expect(log.kept.single.message, 'Bad state: no element in round 3');
    });
  });

  group('RecordError', () {
    test('fingerprints, locates and stamps the occurrence', () async {
      await record(
        _report(
          stack:
              '#0      SeasonRepository.find '
              '(package:infrastructure/src/x.dart:12:5)\n'
              '#1      onRequest (file:///app/routes/seasons/index.dart:40:3)',
        ),
      );

      final kept = log.kept.single;
      expect(kept.fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(kept.problemCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}$')));
      expect(kept.locationFile, 'package:infrastructure/src/x.dart');
      expect(kept.locationLine, 12);
      expect(kept.locationSymbol, 'SeasonRepository.find');
      expect(kept.occurredAt, DateTime.utc(2026, 10, 3, 12));
      expect(kept.userId, _user);
      expect(kept.severity, ErrorSeverity.high);
    });

    test('two identical errors share one fingerprint', () async {
      await record(_report(message: 'Bad state: id 1'));
      await record(_report(message: 'Bad state: id 2'));

      expect(log.kept[0].fingerprint, log.kept[1].fingerprint);
    });

    test('an unknown source is refused and nothing is kept', () async {
      final result = await record(_report(source: 'desktop'));

      expect(result.isErr, isTrue);
      expect(log.kept, isEmpty);
    });

    test('a malformed build, request id or player id is not trusted', () async {
      await record(
        _report(build: 'bad build!', requestId: 'x', userId: 'not-a-uuid'),
      );

      final kept = log.kept.single;
      expect(kept.build, RecordError.unknownBuild);
      expect(kept.requestId, isNull);
      expect(kept.userId, isNull);
    });

    test('every field is capped to what the table accepts', () async {
      await record(
        _report(
          message: 'x' * 5000,
          input: {'blob': List<String>.filled(50, 'y' * 400)},
        ),
      );

      final kept = log.kept.single;
      expect(kept.message.length, 1000);
      expect(
        utf8.encode(kept.requestInputJson!).length,
        lessThanOrEqualTo(RecordError.maxInputBytes),
      );
    });

    test('a blank message falls back to the error type', () async {
      await record(_report(message: '   '));

      expect(log.kept.single.message, 'StateError');
    });
  });
}
