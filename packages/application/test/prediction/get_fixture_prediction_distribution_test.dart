import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_fixture_prediction_repository.dart';

const _season = '11111111-1111-1111-1111-111111111111';
const _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _user = '22222222-2222-2222-2222-222222222222';
const _participant1 = '44444444-4444-4444-4444-444444444444';
const _participant2 = '55555555-5555-5555-5555-555555555555';
const _participant3 = '66666666-6666-6666-6666-666666666666';
const _prediction1 = '77777777-7777-7777-7777-777777777777';
const _prediction2 = '88888888-8888-8888-8888-888888888888';
const _prediction3 = '99999999-9999-9999-9999-999999999999';

FixtureRef _fixtureRef() =>
    (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;
SeasonId _seasonId() => (SeasonId.tryParse(_season) as Ok<SeasonId>).value;
ParticipantId _participant(String value) =>
    (ParticipantId.tryParse(value) as Ok<ParticipantId>).value;
PredictionId _predictionId(String value) =>
    (PredictionId.tryParse(value) as Ok<PredictionId>).value;

SeasonFixture _link() =>
    (SeasonFixture.create(
              seasonId: _seasonId(),
              fixture: _fixtureRef(),
              displayOrder: 0,
            )
            as Ok<SeasonFixture>)
        .value;

FixturePrediction _prediction({
  required String id,
  required String participant,
  required int home,
  required int away,
}) => FixturePrediction.fromStored(
  id: _predictionId(id),
  fixture: _fixtureRef(),
  participantId: _participant(participant),
  homeGoals: home,
  awayGoals: away,
);

AuthenticatedUser _userPrincipal() =>
    AuthenticatedUser(userId: UserId(_user), role: PlatformRole.user);

void main() {
  test('calculates home/away shares and ignores draw predictions', () async {
    final repo = FakeFixturePredictionRepository()..seedSeasonFixture(_link());
    final submitted = DateTime.utc(2026, 9, 12);
    repo
      ..seedPrediction(
        _prediction(
          id: _prediction1,
          participant: _participant1,
          home: 2,
          away: 1,
        ),
        submitted,
      )
      ..seedPrediction(
        _prediction(
          id: _prediction2,
          participant: _participant2,
          home: 0,
          away: 1,
        ),
        submitted,
      )
      ..seedPrediction(
        _prediction(
          id: _prediction3,
          participant: _participant3,
          home: 1,
          away: 1,
        ),
        submitted,
      );

    final result = await GetFixturePredictionDistribution(
      fixturePredictionRepository: repo,
    ).call(principal: _userPrincipal(), seasonId: _season, fixtureId: _fixture);

    final value = (result as Ok<FixturePredictionDistribution>).value;
    expect(value.homeWinPercentage, 50);
    expect(value.awayWinPercentage, 50);
  });

  test('returns zero shares when there are no decisive predictions', () async {
    final repo = FakeFixturePredictionRepository()..seedSeasonFixture(_link());
    repo.seedPrediction(
      _prediction(
        id: _prediction1,
        participant: _participant1,
        home: 1,
        away: 1,
      ),
      DateTime.utc(2026, 9, 12),
    );

    final result = await GetFixturePredictionDistribution(
      fixturePredictionRepository: repo,
    ).call(principal: _userPrincipal(), seasonId: _season, fixtureId: _fixture);

    final value = (result as Ok<FixturePredictionDistribution>).value;
    expect(value.homeWinPercentage, 0);
    expect(value.awayWinPercentage, 0);
  });
}
