import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('FixtureScheduleApi.registerFixtureSchedule (POST /fixtures)', () {
    test(
      '201 -> Ok(FixtureScheduleDto), sends POST with the request body',
      () async {
        const expected = FixtureScheduleDto(
          fixtureId: 'f-1',
          homeTeam: 'Al Hilal',
          awayTeam: 'Al Nassr',
          kickoffAt: '2026-08-20T18:00:00.000Z',
        );
        final ctx = buildTransport(
          (_) async => http.Response(
            jsonEncode(expected.toJson()),
            201,
            headers: const {'content-type': 'application/json'},
          ),
        );

        final result = await FixtureScheduleApi(ctx.transport)
            .registerFixtureSchedule(
              homeTeam: 'Al Hilal',
              awayTeam: 'Al Nassr',
              kickoffAt: '2026-08-20T18:00:00.000Z',
            );

        expect(result, const Result<FixtureScheduleDto>.ok(expected));
        final req = ctx.captured.single;
        expect(req.method, 'POST');
        expect(req.url.path, '/fixtures');
        expect(jsonDecode(req.body), {
          'schema_version': 1,
          'home_team': 'Al Hilal',
          'away_team': 'Al Nassr',
          'kickoff_at': '2026-08-20T18:00:00.000Z',
          'home_team_id': null,
          'away_team_id': null,
        });
      },
    );

    test('401 (non-admin) -> Err, no client-side oracle', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(401, 'auth.insufficient_role', 'admin only'),
      );

      final result = await FixtureScheduleApi(ctx.transport)
          .registerFixtureSchedule(
            homeTeam: 'Al Hilal',
            awayTeam: 'Al Nassr',
            kickoffAt: '2026-08-20T18:00:00.000Z',
          );

      expect(
        (result as Err<FixtureScheduleDto>).error.code,
        'auth.insufficient_role',
      );
    });

    test(
      '400 identical team names -> Err with the domain validation code',
      () async {
        final ctx = buildTransport(
          (_) async => errorEnvelope(
            400,
            'competition.fixture_schedule_same_team',
            'home and away must differ',
          ),
        );

        final result = await FixtureScheduleApi(ctx.transport)
            .registerFixtureSchedule(
              homeTeam: 'Al Hilal',
              awayTeam: 'Al Hilal',
              kickoffAt: '2026-08-20T18:00:00.000Z',
            );

        expect(
          (result as Err<FixtureScheduleDto>).error.code,
          'competition.fixture_schedule_same_team',
        );
      },
    );
  });

  group('FixtureScheduleApi.correctFixtureSchedule (PUT /fixtures/{id})', () {
    test('200 -> Ok(FixtureScheduleDto), sends PUT to the path id', () async {
      const expected = FixtureScheduleDto(
        fixtureId: 'f-1',
        homeTeam: 'Al Hilal SFC',
        awayTeam: 'Al Nassr FC',
        kickoffAt: '2026-08-21T18:00:00.000Z',
      );
      final ctx = buildTransport((_) async => okJson(expected.toJson()));

      final result = await FixtureScheduleApi(ctx.transport)
          .correctFixtureSchedule(
            fixtureId: 'f-1',
            homeTeam: 'Al Hilal SFC',
            awayTeam: 'Al Nassr FC',
            kickoffAt: '2026-08-21T18:00:00.000Z',
          );

      expect(result, const Result<FixtureScheduleDto>.ok(expected));
      final req = ctx.captured.single;
      expect(req.method, 'PUT');
      expect(req.url.path, '/fixtures/f-1');
      expect(jsonDecode(req.body), {
        'schema_version': 1,
        'home_team': 'Al Hilal SFC',
        'away_team': 'Al Nassr FC',
        'kickoff_at': '2026-08-21T18:00:00.000Z',
        'home_team_id': null,
        'away_team_id': null,
      });
    });

    test('correcting an unregistered id (upsert) -> still Ok', () async {
      const expected = FixtureScheduleDto(
        fixtureId: 'unknown-id',
        homeTeam: 'Al Ittihad',
        awayTeam: 'Al Ahli',
        kickoffAt: '2026-08-22T18:00:00.000Z',
      );
      final ctx = buildTransport((_) async => okJson(expected.toJson()));

      final result = await FixtureScheduleApi(ctx.transport)
          .correctFixtureSchedule(
            fixtureId: 'unknown-id',
            homeTeam: 'Al Ittihad',
            awayTeam: 'Al Ahli',
            kickoffAt: '2026-08-22T18:00:00.000Z',
          );

      expect(result, const Result<FixtureScheduleDto>.ok(expected));
    });

    test('405 non-PUT-allowed method surfaced by the server -> Err', () async {
      final ctx = buildTransport((_) async => bareStatus(405));

      final result = await FixtureScheduleApi(ctx.transport)
          .correctFixtureSchedule(
            fixtureId: 'f-1',
            homeTeam: 'Al Hilal',
            awayTeam: 'Al Nassr',
            kickoffAt: '2026-08-20T18:00:00.000Z',
          );

      expect((result as Err<FixtureScheduleDto>).error.code, isNotEmpty);
    });
  });
}
