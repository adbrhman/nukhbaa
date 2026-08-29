import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('CompetitionApi.listCompetitions (GET /competitions)', () {
    test('200 array -> Ok(List<CompetitionDto>) in server order', () async {
      const a = CompetitionDto(
        id: 'c-1',
        name: 'Alpha',
        format: 'football_scoreline',
        visibility: 'public',
      );
      const b = CompetitionDto(
        id: 'c-2',
        name: 'Beta',
        format: 'football_scoreline',
        visibility: 'public',
      );
      final ctx = buildTransport((_) async => okJson([a.toJson(), b.toJson()]));

      final result = await CompetitionApi(ctx.transport).listCompetitions();

      expect(result, const Result<List<CompetitionDto>>.ok([a, b]));
      expect(ctx.captured.single.url.path, '/competitions');
      expect(ctx.captured.single.method, 'GET');
    });

    test('empty catalogue -> Ok(<empty>), not an error', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(ctx.transport).listCompetitions();

      expect((result as Ok<List<CompetitionDto>>).value, isEmpty);
    });

    test('an array element of the wrong type -> malformed_response', () async {
      final ctx = buildTransport(
        (_) async => okJson(<Object>['not-an-object']),
      );

      final result = await CompetitionApi(ctx.transport).listCompetitions();

      expect(
        (result as Err<List<CompetitionDto>>).error.code,
        apiErrorMalformedResponse,
      );
    });

    test('a JSON object (not array) body -> malformed_response', () async {
      final ctx = buildTransport((_) async => okJson({'not': 'a list'}));

      final result = await CompetitionApi(ctx.transport).listCompetitions();

      expect(
        (result as Err<List<CompetitionDto>>).error.code,
        apiErrorMalformedResponse,
      );
    });
  });

  group('CompetitionApi.getCompetition (GET /competitions/{id})', () {
    test('200 -> Ok(CompetitionDto) at the id path', () async {
      const dto = CompetitionDto(
        id: 'c-9',
        name: 'Gamma',
        format: 'football_scoreline',
        visibility: 'public',
      );
      final ctx = buildTransport((_) async => okJson(dto.toJson()));

      final result = await CompetitionApi(ctx.transport).getCompetition('c-9');

      expect(result, const Result<CompetitionDto>.ok(dto));
      expect(ctx.captured.single.url.path, '/competitions/c-9');
    });

    test(
      '404 competition.not_found -> Err(invariant) with that code',
      () async {
        final ctx = buildTransport(
          (_) async => errorEnvelope(404, 'competition.not_found', 'No such.'),
        );

        final result = await CompetitionApi(ctx.transport).getCompetition('x');

        final err = (result as Err<CompetitionDto>).error;
        expect(err.kind, ErrorKind.invariant);
        expect(err.code, 'competition.not_found');
        expect(err.isRetryable, isFalse);
      },
    );

    test('400 malformed id -> Err(validation), distinct from 404', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(400, 'validation.invalid_id', 'Bad id.'),
      );

      final result = await CompetitionApi(ctx.transport).getCompetition('!!');

      expect((result as Err<CompetitionDto>).error.kind, ErrorKind.validation);
    });
  });

  group('CompetitionApi.listCompetitionSeasons '
      '(GET /competitions/{id}/seasons)', () {
    test('200 array -> Ok(List<SeasonDto>) at the seasons path', () async {
      final a = SeasonDto(
        id: 's-1',
        competitionId: 'c-1',
        label: '07/2025',
        startAt: DateTime.utc(2025, 7, 1),
        endAt: DateTime.utc(2025, 8, 1),
      );
      final b = SeasonDto(
        id: 's-2',
        competitionId: 'c-1',
        label: '08/2026',
        startAt: DateTime.utc(2026, 8, 1),
        endAt: DateTime.utc(2026, 9, 1),
      );
      final ctx = buildTransport((_) async => okJson([a.toJson(), b.toJson()]));

      final result = await CompetitionApi(
        ctx.transport,
      ).listCompetitionSeasons('c-1');

      expect(result, Result<List<SeasonDto>>.ok([a, b]));
      expect(ctx.captured.single.url.path, '/competitions/c-1/seasons');
      expect(ctx.captured.single.method, 'GET');
    });

    test(
      'an absent competition is a legitimate empty array (no oracle)',
      () async {
        final ctx = buildTransport((_) async => okJson(<Object>[]));

        final result = await CompetitionApi(
          ctx.transport,
        ).listCompetitionSeasons('gone');

        expect((result as Ok<List<SeasonDto>>).value, isEmpty);
      },
    );

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).listCompetitionSeasons('c-1');

      expect((result as Err<List<SeasonDto>>).error.isRetryable, isTrue);
    });
  });

  group('CompetitionApi.listSeasonRounds (GET /seasons/{id}/rounds)', () {
    test('200 array -> Ok(List<RoundDto>) at the rounds path', () async {
      const r1 = RoundDto(
        id: 'r-1',
        seasonId: 's-1',
        sequence: 1,
        predictionDeadline: '2026-08-01T12:00:00Z',
        status: 'open',
        rulesetVersion: 1,
      );
      const r2 = RoundDto(
        id: 'r-2',
        seasonId: 's-1',
        sequence: 2,
        predictionDeadline: '2026-08-08T12:00:00Z',
        status: 'locked',
        rulesetVersion: 1,
      );
      final ctx = buildTransport(
        (_) async => okJson([r1.toJson(), r2.toJson()]),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).listSeasonRounds('s-1');

      expect(result, const Result<List<RoundDto>>.ok([r1, r2]));
      expect(ctx.captured.single.url.path, '/seasons/s-1/rounds');
      expect(ctx.captured.single.method, 'GET');
    });

    test('an absent season is a legitimate empty array (no oracle)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(
        ctx.transport,
      ).listSeasonRounds('gone');

      expect((result as Ok<List<RoundDto>>).value, isEmpty);
    });

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).listSeasonRounds('s-1');

      expect((result as Err<List<RoundDto>>).error.isRetryable, isTrue);
    });
  });

  group('CompetitionApi.getRound (GET /rounds/{id})', () {
    test('200 -> Ok(RoundDto)', () async {
      const dto = RoundDto(
        id: 'r-1',
        seasonId: 's-1',
        sequence: 3,
        predictionDeadline: '2026-08-01T12:00:00Z',
        status: 'open',
        rulesetVersion: 2,
      );
      final ctx = buildTransport((_) async => okJson(dto.toJson()));

      final result = await CompetitionApi(ctx.transport).getRound('r-1');

      expect(result, const Result<RoundDto>.ok(dto));
      expect(ctx.captured.single.url.path, '/rounds/r-1');
    });

    test('404 competition.round_not_found -> Err(invariant)', () async {
      final ctx = buildTransport(
        (_) async =>
            errorEnvelope(404, 'competition.round_not_found', 'No round.'),
      );

      final result = await CompetitionApi(ctx.transport).getRound('r-x');

      final err = (result as Err<RoundDto>).error;
      expect(err.kind, ErrorKind.invariant);
      expect(err.code, 'competition.round_not_found');
    });
  });

  group('CompetitionApi.browseRoundFixtures (GET /rounds/{id}/fixtures)', () {
    test('200 -> Ok(List<RoundFixtureCardDto>) at the fixtures path', () async {
      const f0 = RoundFixtureCardDto(
        roundId: 'r',
        fixtureId: 'f-a',
        displayOrder: 0,
        homeTeam: 'Al Hilal',
        awayTeam: 'Al Nassr',
        kickoffAt: '2026-08-15T18:00:00.000Z',
      );
      const f1 = RoundFixtureCardDto(
        roundId: 'r',
        fixtureId: 'f-b',
        displayOrder: 1,
        homeTeam: null,
        awayTeam: null,
        kickoffAt: null,
      );
      final ctx = buildTransport(
        (_) async => okJson([f0.toJson(), f1.toJson()]),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).browseRoundFixtures('r');

      expect(result, const Result<List<RoundFixtureCardDto>>.ok([f0, f1]));
      expect(ctx.captured.single.url.path, '/rounds/r/fixtures');
    });

    test('an absent round is a legitimate empty array (no oracle)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(
        ctx.transport,
      ).browseRoundFixtures('gone');

      expect((result as Ok<List<RoundFixtureCardDto>>).value, isEmpty);
    });

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).browseRoundFixtures('r');

      expect(
        (result as Err<List<RoundFixtureCardDto>>).error.isRetryable,
        isTrue,
      );
    });
  });

  group('CompetitionApi.browseSeasonFixtures (GET /seasons/{id}/fixtures)', () {
    test(
      '200 -> Ok(List<SeasonFixtureCardDto>) at the fixtures path',
      () async {
        const f0 = SeasonFixtureCardDto(
          seasonId: 's',
          fixtureId: 'f-a',
          homeTeam: 'Al Hilal',
          awayTeam: 'Al Nassr',
          kickoffAt: '2026-08-15T18:00:00.000Z',
        );
        const f1 = SeasonFixtureCardDto(
          seasonId: 's',
          fixtureId: 'f-b',
          homeTeam: null,
          awayTeam: null,
          kickoffAt: null,
        );
        final ctx = buildTransport(
          (_) async => okJson([f0.toJson(), f1.toJson()]),
        );

        final result = await CompetitionApi(
          ctx.transport,
        ).browseSeasonFixtures('s');

        expect(result, const Result<List<SeasonFixtureCardDto>>.ok([f0, f1]));
        expect(ctx.captured.single.url.path, '/seasons/s/fixtures');
      },
    );

    test('an absent season is a legitimate empty array (no oracle)', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(
        ctx.transport,
      ).browseSeasonFixtures('gone');

      expect((result as Ok<List<SeasonFixtureCardDto>>).value, isEmpty);
    });

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).browseSeasonFixtures('s');

      expect(
        (result as Err<List<SeasonFixtureCardDto>>).error.isRetryable,
        isTrue,
      );
    });
  });

  group('CompetitionApi.linkFixtureToSeason (POST /seasons/{id}/fixtures)', () {
    test(
      '201 -> Ok(SeasonFixtureDto), posts fixture_id/display_order',
      () async {
        const dto = SeasonFixtureDto(
          seasonId: 's',
          fixtureId: 'f-a',
          displayOrder: 2,
        );
        final ctx = buildTransport((_) async => okJson(dto.toJson()));

        final result = await CompetitionApi(
          ctx.transport,
        ).linkFixtureToSeason(seasonId: 's', fixtureId: 'f-a', displayOrder: 2);

        expect(result, const Result<SeasonFixtureDto>.ok(dto));
        expect(ctx.captured.single.method, 'POST');
        expect(ctx.captured.single.url.path, '/seasons/s/fixtures');
        final sent =
            jsonDecode(ctx.captured.single.body) as Map<String, Object?>;
        expect(sent['fixture_id'], 'f-a');
        expect(sent['display_order'], 2);
      },
    );

    test(
      '409 competition.season_fixture_already_linked -> Err(invariant)',
      () async {
        final ctx = buildTransport(
          (_) async => errorEnvelope(
            409,
            'competition.season_fixture_already_linked',
            'Already linked.',
          ),
        );

        final result = await CompetitionApi(
          ctx.transport,
        ).linkFixtureToSeason(seasonId: 's', fixtureId: 'f-a', displayOrder: 0);

        expect(
          (result as Err<SeasonFixtureDto>).error.kind,
          ErrorKind.invariant,
        );
      },
    );

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(
        ctx.transport,
      ).linkFixtureToSeason(seasonId: 's', fixtureId: 'f-a', displayOrder: 0);

      expect((result as Err<SeasonFixtureDto>).error.isRetryable, isTrue);
    });
  });

  group('CompetitionApi.getMatchesFeed (GET /feed/matches)', () {
    test('200 array -> Ok(List<MatchFeedItemDto>)', () async {
      const item = MatchFeedItemDto(
        competitionName: 'Premier League',
        roundId: 'r-1',
        rulesetVersion: 3,
        fixture: RoundFixtureCardDto(
          roundId: 'r-1',
          fixtureId: 'f-a',
          displayOrder: 0,
          homeTeam: 'Al Hilal',
          awayTeam: 'Al Nassr',
          kickoffAt: '2026-08-20T18:00:00.000Z',
        ),
      );
      final ctx = buildTransport((_) async => okJson([item.toJson()]));

      final result = await CompetitionApi(ctx.transport).getMatchesFeed();

      expect(result, const Result<List<MatchFeedItemDto>>.ok([item]));
      expect(ctx.captured.single.url.path, '/feed/matches');
      expect(ctx.captured.single.method, 'GET');
    });

    test('no open rounds anywhere -> Ok(<empty>), not an error', () async {
      final ctx = buildTransport((_) async => okJson(<Object>[]));

      final result = await CompetitionApi(ctx.transport).getMatchesFeed();

      expect((result as Ok<List<MatchFeedItemDto>>).value, isEmpty);
    });

    test('503 -> Err(transient) retryable', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
      );

      final result = await CompetitionApi(ctx.transport).getMatchesFeed();

      expect((result as Err<List<MatchFeedItemDto>>).error.isRetryable, isTrue);
    });
  });

  group(
    'CompetitionApi.getCurrentSeason '
    '(GET /competitions/{id}/seasons/current)',
    () {
      test('200 -> Ok(SeasonDto) at the current path', () async {
        final dto = SeasonDto(
          id: 's-1',
          competitionId: 'c-1',
          label: '08/2026',
          startAt: DateTime.utc(2026, 8, 1),
          endAt: DateTime.utc(2026, 9, 1),
        );
        final ctx = buildTransport((_) async => okJson(dto.toJson()));

        final result = await CompetitionApi(
          ctx.transport,
        ).getCurrentSeason('c-1');

        expect(result, Result<SeasonDto?>.ok(dto));
        expect(
          ctx.captured.single.url.path,
          '/competitions/c-1/seasons/current',
        );
        expect(ctx.captured.single.method, 'GET');
      });

      test(
        'a literal JSON null body -> Ok(null), no season covers now',
        () async {
          final ctx = buildTransport(
            (_) async => http.Response(
              'null',
              200,
              headers: const {'content-type': 'application/json'},
            ),
          );

          final result = await CompetitionApi(
            ctx.transport,
          ).getCurrentSeason('c-1');

          expect((result as Ok<SeasonDto?>).value, isNull);
        },
      );

      test('503 -> Err(transient) retryable', () async {
        final ctx = buildTransport(
          (_) async => errorEnvelope(503, 'transient.upstream', 'Retry.'),
        );

        final result = await CompetitionApi(
          ctx.transport,
        ).getCurrentSeason('c-1');

        expect((result as Err<SeasonDto?>).error.isRetryable, isTrue);
      });
    },
  );
}
