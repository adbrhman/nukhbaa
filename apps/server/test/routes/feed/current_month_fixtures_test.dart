import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in
// isolation.
// ignore: always_use_package_imports
import '../../../routes/feed/current-month-fixtures/index.dart'
    as current_month_fixtures_route;
import '../competition_route_harness.dart';

/// Route test for `GET /feed/current-month-fixtures` -- the current-month
/// fixture aggregate read (Monthly Competitions transition,
/// project-context.md section 9).
///
/// Tested through the real wiring
/// (`context.read<Future<CompositionRoot>>()` ->
/// `root.listCurrentMonthFixtures()`) over the in-memory
/// [InMemoryCompetitionRepository], mirroring `matches_test.dart`.
void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  Competition competition(String id, String name) =>
      (Competition.create(
                id: CompetitionId(id),
                name: name,
                format: FormatType.footballScoreline,
                visibility: CompetitionVisibility.public,
              )
              as Ok<Competition>)
          .value;

  CompetitionSeason season(String id, String competitionId) =>
      (CompetitionSeason.create(
                id: SeasonId(id),
                competitionId: CompetitionId(competitionId),
                label: '08/2026',
                startAt: DateTime.utc(2026, 8, 1),
                endAt: DateTime.utc(2026, 9, 1),
              )
              as Ok<CompetitionSeason>)
          .value;

  late InMemoryCompetitionRepository repo;
  late _InMemoryFixturePredictionRepository preds;
  late InMemoryFixtureScheduleRepository schedules;

  CompositionRoot rootWith() {
    repo = InMemoryCompetitionRepository();
    preds = _InMemoryFixturePredictionRepository();
    schedules = InMemoryFixtureScheduleRepository();
    return CompositionRoot.forTesting(
      listCurrentMonthFixtures: ListCurrentMonthFixtures(
        competitionRepository: repo,
        fixturePredictionRepository: preds,
        fixtureScheduleRepository: schedules,
        clock: FixedClock(now),
      ),
    );
  }

  test(
    'returns 200 with the feed, one entry per current-month fixture',
    () async {
      final root = rootWith();
      repo.competitions[kCompetitionId] = competition(
        kCompetitionId,
        'Premier League',
      );
      repo.seasons[kSeasonId] = season(kSeasonId, kCompetitionId);
      preds.linkFixture(kSeasonId, kFixtureId);

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      final response = await current_month_fixtures_route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      final items = body.cast<Map<String, Object?>>();
      expect(items, hasLength(1));
      expect(items.single['competition_id'], kCompetitionId);
      expect(items.single['competition_name'], 'Premier League');
      expect(items.single['season_label'], '08/2026');
      final fixture = items.single['fixture']! as Map<Object?, Object?>;
      expect(fixture['fixture_id'], kFixtureId);
      expect(fixture['season_id'], kSeasonId);
    },
  );

  test('no public competitions is a legitimate 200 empty array (no '
      'existence oracle)', () async {
    final context = wireContext(
      root: rootWith(),
      principal: userPrincipal(),
      method: HttpMethod.get,
    );

    final response = await current_month_fixtures_route.onRequest(context);

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.json() as List<Object?>;
    expect(body, isEmpty);
  });

  test(
    'a current season with no linked fixtures contributes nothing',
    () async {
      final root = rootWith();
      repo.competitions[kCompetitionId] = competition(
        kCompetitionId,
        'Premier League',
      );
      repo.seasons[kSeasonId] = season(kSeasonId, kCompetitionId);
      // No fixture links seeded.

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      final response = await current_month_fixtures_route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      expect(body, isEmpty);
    },
  );

  test('an unsupported method (POST) is 405', () async {
    final context = wireContext(root: rootWith(), principal: userPrincipal());

    final response = await current_month_fixtures_route.onRequest(context);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}

/// A minimal in-memory [FixturePredictionRepository] for this route test
/// file only (kept local, mirrors the equivalent private fakes in
/// `season_fixtures_link_test.dart` / `fixture_prediction_scoring_test.dart`
/// -- not a substitute for the application package's own fake). Only
/// [listSeasonFixtures] is exercised here (plus the [linkFixture] helper
/// the test uses to seed it); every other member is unreachable from this
/// route and left unimplemented on purpose (a call would be a test-scope
/// bug, not a production path). Never throws for the members it does
/// implement.
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final Map<String, List<FixtureRef>> _bySeasonId = {};

  /// Seeds a fixture link for [seasonId] (test helper, not part of the
  /// port).
  void linkFixture(String seasonId, String fixtureId) {
    final fixture = (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;
    _bySeasonId.putIfAbsent(seasonId, () => []).add(fixture);
  }

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    return Result.ok(
      List<FixtureRef>.unmodifiable(_bySeasonId[seasonId.value] ?? const []),
    );
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) =>
      throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) => throw UnimplementedError('not exercised by this route test file');

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) =>
      throw UnimplementedError('not exercised by this route test file');
}
