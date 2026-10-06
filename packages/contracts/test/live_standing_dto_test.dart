import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips through JSON', () {
    const dto = LiveStandingDto(
      fixtures: [
        LiveFixtureStandingDto(
          fixtureId: 'f1',
          homeGoals: 1,
          awayGoals: 0,
          minute: 63,
          finished: false,
          myPoints: 6,
        ),
      ],
      duels: [
        LiveDuelStandingDto(
          fixtureId: 'f1',
          opponentName: 'Rival',
          myPoints: 3,
          opponentPoints: 0,
        ),
      ],
      rankNow: 3,
      rankIfEnded: 1,
      pointsNow: 3,
      pointsIfEnded: 9,
      players: 3,
    );

    final back = LiveStandingDto.fromJson(dto.toJson());

    final LiveFixtureStandingDto line = back.fixture('f1')!;
    expect((line.homeGoals, line.awayGoals, line.minute), (1, 0, 63));
    expect((line.finished, line.myPoints), (false, 6));
    expect(back.fixture('f9'), isNull);
    final LiveDuelStandingDto duel = back.duels.single;
    expect(
      (duel.opponentName, duel.myPoints, duel.opponentPoints),
      ('Rival', 3, 0),
    );
    expect((back.rankNow, back.rankIfEnded), (3, 1));
    expect((back.pointsNow, back.pointsIfEnded, back.players), (3, 9, 3));
    expect(dto.toJson()['schema_version'], 1);
  });

  test('nothing in play reads as empty, and a broken line is left out', () {
    final dto = LiveStandingDto.fromJson(const {
      'fixtures': [
        {'fixture_id': 'f1', 'home_goals': 'x', 'away_goals': 0},
      ],
    });

    expect(dto.fixtures, isEmpty);
    expect(dto.duels, isEmpty);
    expect(dto.rankNow, isNull);
    expect(dto.players, 0);
  });
}
