import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../prediction/fake_fixture_prediction_repository.dart';
import 'fake_fixture_score_repository.dart';
import 'fakes.dart';

const _season = '11111111-1111-1111-1111-111111111111';
const _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _memberUser = '22222222-2222-2222-2222-222222222222';
const _outsiderUser = '33333333-3333-3333-3333-333333333333';
const _participant = '44444444-4444-4444-4444-444444444444';

({
  GetFixtureScores useCase,
  FakeCompetitionRepository competition,
  FakeFixturePredictionRepository predictions,
  FakeFixtureScoreRepository scores,
})
_harness() {
  final competition = FakeCompetitionRepository();
  final predictions = FakeFixturePredictionRepository();
  final scores = FakeFixtureScoreRepository();
  final useCase = GetFixtureScores(
    competitionRepository: competition,
    fixturePredictionRepository: predictions,
    fixtureScoreRepository: scores,
  );
  return (
    useCase: useCase,
    competition: competition,
    predictions: predictions,
    scores: scores,
  );
}

void _enrolMember(FakeCompetitionRepository competition) {
  competition.seedParticipant(
    scoringParticipant(
      id: _participant,
      seasonId: _season,
      userId: _memberUser,
    ),
  );
}

SeasonFixture _link({String fixture = _fixture}) =>
    (SeasonFixture.create(
          seasonId: (SeasonId.tryParse(_season) as Ok<SeasonId>).value,
          fixture: (FixtureRef.tryParse(fixture) as Ok<FixtureRef>).value,
          displayOrder: 0,
        )
        as Ok<SeasonFixture>)
    .value;

void main() {
  group('GetFixtureScores — authorization / membership', () {
    test('a non-member is refused scoring.not_a_participant', () async {
      final h = _harness();
      h.predictions.seedSeasonFixture(_link());
      final result = await h.useCase.call(
        principal: userPrincipal(_outsiderUser),
        seasonId: _season,
        fixtureId: _fixture,
      );
      final error = (result as Err<List<ParticipantFixtureScore>>).error;
      expect(error.code, 'scoring.not_a_participant');
      expect(error.kind, ErrorKind.authorization);
    });

    test('a malformed season id is a validation error', () async {
      final h = _harness();
      final result = await h.useCase.call(
        principal: userPrincipal(_memberUser),
        seasonId: 'not-a-uuid',
        fixtureId: _fixture,
      );
      expect(
        (result as Err<List<ParticipantFixtureScore>>).error.kind,
        ErrorKind.validation,
      );
    });
  });

  group('GetFixtureScores — season/fixture linkage', () {
    test('a fixture not linked to the season is rejected', () async {
      final h = _harness();
      _enrolMember(h.competition);
      final result = await h.useCase.call(
        principal: userPrincipal(_memberUser),
        seasonId: _season,
        fixtureId: _fixture,
      );
      final error = (result as Err<List<ParticipantFixtureScore>>).error;
      expect(error.code, 'prediction.fixture_not_in_season');
      expect(error.kind, ErrorKind.invariant);
    });
  });

  group('GetFixtureScores — live/partial read', () {
    test('an empty list before scoring is a legitimate result', () async {
      final h = _harness();
      _enrolMember(h.competition);
      h.predictions.seedSeasonFixture(_link());
      final result = await h.useCase.call(
        principal: userPrincipal(_memberUser),
        seasonId: _season,
        fixtureId: _fixture,
      );
      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      expect((result as Ok<List<ParticipantFixtureScore>>).value, isEmpty);
    });

    test('a member reads the scored results for a linked fixture', () async {
      final h = _harness();
      _enrolMember(h.competition);
      h.predictions.seedSeasonFixture(_link());
      final fixtureRef = (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;
      await h.scores.saveFixtureScores([
        ParticipantFixtureScore.fromStored(
          fixture: fixtureRef,
          participantId:
              (ParticipantId.tryParse(_participant) as Ok<ParticipantId>).value,
          rulesetVersion: 1,
          result: FixtureScoreResult(
            fixture: fixtureRef,
            grade: FixtureScoreGrade.exactScoreline,
            points: 3,
          ),
        ),
      ]);
      final result = await h.useCase.call(
        principal: userPrincipal(_memberUser),
        seasonId: _season,
        fixtureId: _fixture,
      );
      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      expect(
        (result as Ok<List<ParticipantFixtureScore>>).value.single.points,
        3,
      );
    });
  });
}
