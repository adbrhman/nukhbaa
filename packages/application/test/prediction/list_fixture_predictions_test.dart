import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart' show FixedClock, userPrincipal;
import '../ledger/fakes.dart' show FakeParticipantReader;
import '../scoring/fakes.dart' show scoringParticipant;
import 'fake_fixture_prediction_repository.dart';
import 'fake_fixture_schedule_repository.dart';

const _season = '11111111-1111-1111-1111-111111111111';
const _fixture = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _memberUser = '22222222-2222-2222-2222-222222222222';
const _outsiderUser = '33333333-3333-3333-3333-333333333333';
const _memberParticipant = '44444444-4444-4444-4444-444444444444';
const _otherParticipant = '55555555-5555-5555-5555-555555555555';

final DateTime _kickoff = DateTime.utc(2026, 9, 28, 18);

({
  ListFixturePredictions useCase,
  FakeCompetitionRepository competition,
  FakeFixturePredictionRepository predictions,
  FakeFixtureScheduleRepository schedules,
  FakeParticipantReader participants,
})
_harness({required DateTime now}) {
  final competition = FakeCompetitionRepository();
  final predictions = FakeFixturePredictionRepository();
  final schedules = FakeFixtureScheduleRepository();
  final participants = FakeParticipantReader();
  return (
    useCase: ListFixturePredictions(
      competitionRepository: competition,
      fixturePredictionRepository: predictions,
      fixtureScheduleRepository: schedules,
      participantReader: participants,
      clock: FixedClock(now),
    ),
    competition: competition,
    predictions: predictions,
    schedules: schedules,
    participants: participants,
  );
}

FixtureRef _ref() => (FixtureRef.tryParse(_fixture) as Ok<FixtureRef>).value;

/// A member of the season, a linked and scheduled fixture, and two stored
/// predictions (the member's own and another participant's).
void _arrange(
  ({
    ListFixturePredictions useCase,
    FakeCompetitionRepository competition,
    FakeFixturePredictionRepository predictions,
    FakeFixtureScheduleRepository schedules,
    FakeParticipantReader participants,
  })
  h, {
  bool scheduled = true,
}) {
  final member = scoringParticipant(
    id: _memberParticipant,
    seasonId: _season,
    userId: _memberUser,
  );
  final other = scoringParticipant(
    id: _otherParticipant,
    seasonId: _season,
    userId: '66666666-6666-6666-6666-666666666666',
  );
  h.competition.seedParticipant(member);
  h.participants
    ..seed(member)
    ..seed(other);
  h.predictions.seedSeasonFixture(
    (SeasonFixture.create(
              seasonId: (SeasonId.tryParse(_season) as Ok<SeasonId>).value,
              fixture: _ref(),
              displayOrder: 0,
            )
            as Ok<SeasonFixture>)
        .value,
  );
  if (scheduled) {
    h.schedules.seed(
      FixtureSchedule.fromStored(
        fixture: _ref(),
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        kickoffAt: _kickoff,
      ),
    );
  }
  for (final (id, home, away) in [
    (_memberParticipant, 2, 1),
    (_otherParticipant, 0, 3),
  ]) {
    h.predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: (PredictionId.tryParse(id) as Ok<PredictionId>).value,
        fixture: _ref(),
        participantId: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
        homeGoals: home,
        awayGoals: away,
      ),
      DateTime.utc(2026, 9, 28, 12),
    );
  }
}

Future<Result<FixturePredictionReveal>> _call(
  ListFixturePredictions useCase, {
  String user = _memberUser,
}) => useCase.call(
  principal: userPrincipal(user),
  seasonId: _season,
  fixtureId: _fixture,
);

void main() {
  group('ListFixturePredictions -- the kickoff gate', () {
    test('one minute before kickoff nothing is revealed', () async {
      final h = _harness(now: _kickoff.subtract(const Duration(minutes: 1)));
      _arrange(h);

      final result = await _call(h.useCase);

      final error = (result as Err<FixturePredictionReveal>).error;
      expect(error.code, 'prediction.fixture_not_started');
      expect(error.kind, ErrorKind.invariant);
    });

    test('at the kickoff instant every prediction is revealed', () async {
      final h = _harness(now: _kickoff);
      _arrange(h);

      final result = await _call(h.useCase);

      final reveal = (result as Ok<FixturePredictionReveal>).value;
      expect(reveal.predictions, hasLength(2));
      expect(
        {
          for (final view in reveal.predictions)
            view.prediction.participantId.value:
                '${view.prediction.homeGoals}-${view.prediction.awayGoals}',
        },
        {_memberParticipant: '2-1', _otherParticipant: '0-3'},
      );
      expect(reveal.displayNames.keys, {_memberParticipant, _otherParticipant});
    });

    test('a fixture with no registered kickoff stays hidden', () async {
      final h = _harness(now: _kickoff.add(const Duration(days: 1)));
      _arrange(h, scheduled: false);

      final result = await _call(h.useCase);

      expect(
        (result as Err<FixturePredictionReveal>).error.code,
        'prediction.fixture_not_started',
      );
    });
  });

  group('ListFixturePredictions -- who may look', () {
    test('a non-member is refused even after kickoff', () async {
      final h = _harness(now: _kickoff.add(const Duration(hours: 1)));
      _arrange(h);

      final result = await _call(h.useCase, user: _outsiderUser);

      final error = (result as Err<FixturePredictionReveal>).error;
      expect(error.code, 'prediction.not_a_participant');
      expect(error.kind, ErrorKind.authorization);
    });

    test('a fixture outside the season is refused', () async {
      final h = _harness(now: _kickoff.add(const Duration(hours: 1)));
      final member = scoringParticipant(
        id: _memberParticipant,
        seasonId: _season,
        userId: _memberUser,
      );
      h.competition.seedParticipant(member);

      final result = await _call(h.useCase);

      expect(
        (result as Err<FixturePredictionReveal>).error.code,
        'prediction.fixture_not_in_season',
      );
    });
  });
}
