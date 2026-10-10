/// `GET /seasons/{id}/predictions-board` (2026-10-11) from the real entry
/// point: the route handler, the real `GetPredictionsBoard` over the real
/// `ListFixturePredictions` gate and the real mappers, over in-memory
/// stores. One answer carries what the three per-fixture routes carried;
/// a fixture not kicked off yet comes back as a refused column without
/// hiding the others; a passing failure of the batched reads is a `503`.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/predictions-board/index.dart' as board_route;
import 'competition_route_harness.dart';

const _started = '66666666-6666-6666-6666-666666666666';
const _later = '77777777-7777-7777-7777-777777777777';
const _myParticipant = '99999999-9999-9999-9999-999999999999';
const _otherParticipant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _otherUser = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

/// 2026-10-10 19:00 UTC: [_started] kicked off at 18:00, [_later] kicks
/// off at 20:00.
final _now = DateTime.utc(2026, 10, 10, 19);

FixtureRef _ref(String id) => (FixtureRef.tryParse(id) as Ok<FixtureRef>).value;

SeasonId get _season => (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value;

Participant _participant(String id, String userId) => Participant.fromStored(
  id: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
  seasonId: _season,
  userId: (UserId.tryParse(userId) as Ok<UserId>).value,
  status: ParticipantStatus.active,
  joinedAt: DateTime.utc(2026, 9),
);

CompositionRoot _root({
  bool member = true,
  bool scoresDown = false,
  bool reactionsDown = false,
}) {
  final competition = InMemoryCompetitionRepository();
  final me = _participant(_myParticipant, kUserId);
  final other = _participant(_otherParticipant, _otherUser);
  if (member) {
    competition.participants.add(me);
  }
  final names = InMemoryParticipantReader()
    ..add(me)
    ..add(other);
  final schedules = InMemoryFixtureScheduleRepository()
    ..seed(
      FixtureSchedule.fromStored(
        fixture: _ref(_started),
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        kickoffAt: DateTime.utc(2026, 10, 10, 18),
      ),
    )
    ..seed(
      FixtureSchedule.fromStored(
        fixture: _ref(_later),
        homeTeam: 'Inter',
        awayTeam: 'Parma',
        kickoffAt: DateTime.utc(2026, 10, 10, 20),
      ),
    );
  final predictions = _Predictions();
  for (final id in [_started, _later]) {
    predictions.links.add(
      (SeasonFixture.create(
                seasonId: _season,
                fixture: _ref(id),
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value,
    );
  }
  for (final (id, home, away) in [
    (_myParticipant, 2, 1),
    (_otherParticipant, 0, 0),
  ]) {
    for (final fixture in [_started, _later]) {
      predictions.stored.add(
        FixturePredictionView(
          prediction: FixturePrediction.fromStored(
            id: (PredictionId.tryParse(id) as Ok<PredictionId>).value,
            fixture: _ref(fixture),
            participantId:
                (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
            homeGoals: home,
            awayGoals: away,
          ),
          submittedAt: DateTime.utc(2026, 10, 10, 12),
        ),
      );
    }
  }
  final scores = _Scores(down: scoresDown)
    ..seed(_started, _myParticipant, FixtureScoreGrade.exactScoreline, 3);
  final reveal = ListFixturePredictions(
    competitionRepository: competition,
    fixturePredictionRepository: predictions,
    fixtureScheduleRepository: schedules,
    participantReader: names,
    clock: FixedClock(_now),
  );
  return CompositionRoot.forTesting(
    getPredictionsBoard: GetPredictionsBoard(
      reveal: reveal,
      scores: scores,
      results: _Results(),
      reactions: _Reactions(down: reactionsDown),
    ),
  );
}

Future<Response> _get(
  CompositionRoot root, {
  String? fixtures = '$_started,$_later',
}) => board_route.onRequest(
  wireContext(
    root: root,
    principal: userPrincipal(),
    method: HttpMethod.get,
    queryParameters: fixtures == null
        ? const <String, String>{}
        : <String, String>{'fixtures': fixtures},
  ),
  kSeasonId,
);

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

Map<Object?, Object?> _map(Object? raw) => raw! as Map<Object?, Object?>;

void main() {
  test('one answer: predictions, scores, result and reactions of a '
      'started fixture; the later one refused in its own column', () async {
    final response = await _get(_root());

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['season_id'], kSeasonId);
    final columns = _list(body['columns']);
    expect([for (final c in columns) c['fixture_id']], [_started, _later]);

    final started = columns.first;
    expect(started['error_code'], isNull);
    final predictions = _list(started['predictions']);
    expect(predictions, hasLength(2));
    expect(
      {for (final p in predictions) p['participant_id']},
      {_myParticipant, _otherParticipant},
    );
    final scores = _map(started['scores']);
    expect(scores['fixture_id'], _started);
    expect(scores['result_home_goals'], 2);
    expect(scores['result_away_goals'], 1);
    final scoreList = _list(scores['scores']);
    expect(scoreList.single['participant_id'], _myParticipant);
    expect(scoreList.single['points'], 3);
    final tally = _list(_map(started['reactions'])['reactions']).single;
    expect(tally['participant_id'], _otherParticipant);
    expect(tally['mine'], 'fire');

    final later = columns.last;
    expect(later['error_code'], 'prediction.fixture_not_started');
    expect(later['retryable'], false);
    expect(later['predictions'], isEmpty);
    expect(later['scores'], isNull);
  });

  test('a player outside the season sees every column refused', () async {
    final response = await _get(_root(member: false));

    expect(response.statusCode, HttpStatus.ok);
    final columns = _list((await decodeBody(response))['columns']);
    expect(
      [for (final c in columns) c['error_code']],
      ['prediction.not_a_participant', 'prediction.not_a_participant'],
    );
  });

  test('unreadable reactions leave the predictions on the board', () async {
    final response = await _get(_root(reactionsDown: true));

    final started = _list((await decodeBody(response))['columns']).first;
    expect(_list(started['predictions']), hasLength(2));
    expect(started['reactions'], isNull);
  });

  test('a passing failure of the scores is a 503', () async {
    final response = await _get(_root(scoresDown: true));

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect((await decodeBody(response))['code'], 'db.down');
  });

  test('no fixture, too many, or a malformed id is 400', () async {
    final none = await _get(_root(), fixtures: null);
    final tooMany = await _get(
      _root(),
      fixtures: [
        for (var i = 0; i < 41; i++)
          '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
      ].join(','),
    );
    final malformed = await _get(_root(), fixtures: 'not-a-fixture');

    expect(none.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(none))['code'], 'board.fixtures_invalid');
    expect(tooMany.statusCode, HttpStatus.badRequest);
    expect(malformed.statusCode, HttpStatus.badRequest);
  });

  test('a fixture asked twice is answered once', () async {
    final response = await _get(_root(), fixtures: '$_started,$_started');

    expect(_list((await decodeBody(response))['columns']), hasLength(1));
  });

  test('a non-GET method is 405', () async {
    final response = await board_route.onRequest(
      wireContext(root: _root(), principal: userPrincipal()),
      kSeasonId,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}

final class _Scores implements FixtureScoreRepository {
  _Scores({required this.down});

  final bool down;
  final List<ParticipantFixtureScore> stored = [];

  void seed(
    String fixtureId,
    String participantId,
    FixtureScoreGrade grade,
    int points,
  ) {
    final fixture = _ref(fixtureId);
    stored.add(
      ParticipantFixtureScore.fromStored(
        fixture: fixture,
        participantId:
            (ParticipantId.tryParse(participantId) as Ok<ParticipantId>).value,
        rulesetVersion: 1,
        result: FixtureScoreResult(
          fixture: fixture,
          grade: grade,
          points: points,
        ),
      ),
    );
  }

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async => const Result.ok(null);

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok([
    for (final s in stored)
      if (s.fixture == fixture) s,
  ]);

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (down) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok([
      for (final s in stored)
        if (fixtures.contains(s.fixture)) s,
    ]);
  }
}

/// The started fixture ended 2-1.
final class _Results implements FixtureResultRepository {
  @override
  Future<Result<void>> upsert(
    FixtureResult result,
    DateTime recordedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) async =>
      const Result.ok(null);

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async => Result.ok([
    if (fixtures.contains(_ref(_started)))
      FixtureResult.fromStored(
        fixture: _ref(_started),
        homeGoals: 2,
        awayGoals: 1,
      ),
  ]);
}

/// The caller gave fire to the other player's prediction.
final class _Reactions implements PredictionReactionRepository {
  _Reactions({required this.down});

  final bool down;

  @override
  Future<Result<PredictionReactionWrite>> upsert({
    required String id,
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
    required ReactionKind kind,
    required DateTime reactedAt,
  }) => throw StateError('the board never writes');

  @override
  Future<Result<bool>> remove({
    required FixtureRef fixture,
    required ParticipantId target,
    required UserId reactor,
  }) => throw StateError('the board never writes');

  @override
  Future<Result<List<PredictionReactionTally>>> tallies({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required UserId viewer,
  }) async {
    if (down) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok([
      PredictionReactionTally(
        targetParticipantId:
            (ParticipantId.tryParse(_otherParticipant) as Ok<ParticipantId>)
                .value,
        counts: const {ReactionKind.fire: 1},
        mine: ReactionKind.fire,
      ),
    ]);
  }
}

final class _Predictions implements FixturePredictionRepository {
  final List<SeasonFixture> links = [];
  final List<FixturePredictionView> stored = [];

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    for (final link in links) {
      if (link.seasonId == seasonId && link.fixture == fixture) {
        return Result.ok(link);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(false);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok([
    for (final view in stored)
      if (view.prediction.fixture == fixture) view,
  ]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok(<FixtureRef>[]);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok(<FixturePredictionView>[]);
}
