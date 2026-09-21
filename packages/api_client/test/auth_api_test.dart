import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AuthApi.me', () {
    test(
      '200 -> Ok(MeResponseDto), sends GET /me with bearer + accept',
      () async {
        const expected = MeResponseDto(
          user: AuthenticatedUserDto(
            userId: 'u-1',
            role: 'user',
            status: 'active',
            email: 'a@example.com',
          ),
        );
        final ctx = buildTransport(
          (_) async => okJson(expected.toJson()),
          token: 'jwt-abc',
        );

        final result = await AuthApi(ctx.transport).me();

        expect(result, const Result<MeResponseDto>.ok(expected));
        final req = ctx.captured.single;
        expect(req.method, 'GET');
        expect(req.url.path, '/me');
        expect(req.headers['authorization'], 'Bearer jwt-abc');
        expect(req.headers['accept'], 'application/json');
      },
    );

    test(
      'omits Authorization header when the token provider yields null',
      () async {
        const body = MeResponseDto(
          user: AuthenticatedUserDto(
            userId: 'u',
            role: 'user',
            status: 'active',
          ),
        );
        final ctx = buildTransport(
          (_) async => okJson(body.toJson()),
          token: null,
        );

        await AuthApi(ctx.transport).me();

        expect(
          ctx.captured.single.headers.containsKey('authorization'),
          isFalse,
        );
      },
    );

    test('401 -> Err(authorization) with the server code/message', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(401, 'auth.token_expired', 'Token expired.'),
      );

      final result = await AuthApi(ctx.transport).me();

      final err = (result as Err<MeResponseDto>).error;
      expect(err.kind, ErrorKind.authorization);
      expect(err.code, 'auth.token_expired');
      expect(err.message, 'Token expired.');
      expect(err.isRetryable, isFalse);
    });

    test('503 -> Err(transient), retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'health.db_unreachable', 'Down.'),
      );

      final result = await AuthApi(ctx.transport).me();

      final err = (result as Err<MeResponseDto>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.isRetryable, isTrue);
    });

    test('network failure -> Err(transient, network_unreachable)', () async {
      final ctx = buildTransport((_) async => throw Exception('socket reset'));

      final result = await AuthApi(ctx.transport).me();

      final err = (result as Err<MeResponseDto>).error;
      expect(err.kind, ErrorKind.transient);
      expect(err.code, apiErrorNetworkUnreachable);
      expect(err.isRetryable, isTrue);
    });

    test('malformed 200 body -> Err(validation, malformed_response)', () async {
      final ctx = buildTransport((_) async => okJson({'unexpected': 'shape'}));

      final result = await AuthApi(ctx.transport).me();

      final err = (result as Err<MeResponseDto>).error;
      expect(err.kind, ErrorKind.validation);
      expect(err.code, apiErrorMalformedResponse);
    });

    test(
      '200 body that is a JSON array (not object) -> malformed_response',
      () async {
        final ctx = buildTransport((_) async => okJson(<Object>[]));

        final result = await AuthApi(ctx.transport).me();

        expect(
          (result as Err<MeResponseDto>).error.code,
          apiErrorMalformedResponse,
        );
      },
    );
  });

  group('AuthApi.myDailyChallenge', () {
    test('200 -> Ok(MyDailyChallengeDto), GET /me/daily-challenge', () async {
      const expected = MyDailyChallengeDto(
        day: '2026-09-20',
        total: 3,
        predicted: 2,
        complete: false,
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).myDailyChallenge();

      expect(result, const Result<MyDailyChallengeDto>.ok(expected));
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/daily-challenge');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('a day with no fixtures parses as total 0, not an error', () async {
      final ctx = buildTransport(
        (_) async => okJson(
          const MyDailyChallengeDto(
            day: '2026-09-21',
            total: 0,
            predicted: 0,
            complete: false,
          ).toJson(),
        ),
      );

      final result = await AuthApi(ctx.transport).myDailyChallenge();

      final value = (result as Ok<MyDailyChallengeDto>).value;
      expect(value.total, 0);
      expect(value.complete, isFalse);
    });
  });

  group('AuthApi.myWeeklyLeague', () {
    test('200 -> Ok(MyWeeklyLeagueDto), GET /me/weekly-league', () async {
      const expected = MyWeeklyLeagueDto(
        weekStart: '2026-09-21',
        weekEnd: '2026-09-27',
        tier: 1,
        groupIndex: 0,
        myRank: 3,
        promotionZone: 5,
        relegationZone: 5,
        entries: [
          WeeklyLeagueEntryDto(
            rank: 3,
            userId: 'u-1',
            displayName: 'Nora',
            points: 7,
            exactCount: 1,
            decidedCount: 4,
            projectedOutcome: 'held',
            isMe: true,
          ),
        ],
      );
      final ctx = buildTransport(
        (_) async => okJson(expected.toJson()),
        token: 'jwt-abc',
      );

      final result = await AuthApi(ctx.transport).myWeeklyLeague();

      expect(result, const Result<MyWeeklyLeagueDto>.ok(expected));
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/me/weekly-league');
      expect(req.headers['authorization'], 'Bearer jwt-abc');
    });

    test('empty entries list parses without error', () async {
      final ctx = buildTransport(
        (_) async => okJson(
          const MyWeeklyLeagueDto(
            weekStart: '2026-09-21',
            weekEnd: '2026-09-27',
            tier: 1,
            groupIndex: 0,
            myRank: 0,
            promotionZone: 0,
            relegationZone: 0,
            entries: [],
          ).toJson(),
        ),
      );

      final result = await AuthApi(ctx.transport).myWeeklyLeague();

      final value = (result as Ok<MyWeeklyLeagueDto>).value;
      expect(value.entries, isEmpty);
      expect(value.myRank, 0);
    });
  });
}
