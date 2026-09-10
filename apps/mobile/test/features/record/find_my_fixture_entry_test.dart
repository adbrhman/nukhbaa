/// Pins how "my points" finds the viewer's row: a three-way tie on rank 1
/// must still resolve to the viewer by participant id (it used to fall
/// back to the season record and print 0 points).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/record/my_points_screen.dart';

FixtureLeaderboardEntryDto _entry(String id, String name, int rank, int pts) =>
    FixtureLeaderboardEntryDto(
      rank: rank,
      participantId: id,
      displayName: name,
      totalPoints: pts,
      fixturesScored: 30,
    );

FixturePredictionDto _prediction(String participantId, String? seasonId) =>
    FixturePredictionDto(
      id: 'fp-$participantId',
      participantId: participantId,
      fixtureId: 'f-1',
      submittedAt: '2026-09-10T00:00:00Z',
      homeGoals: 1,
      awayGoals: 0,
      seasonId: seasonId,
    );

final List<FixtureLeaderboardEntryDto> _tiedBoard =
    <FixtureLeaderboardEntryDto>[
      _entry('p-1', 'Ahmad', 1, 21),
      _entry('p-2', 'Fares', 1, 21),
      _entry('p-3', 'Me', 1, 21),
      _entry('p-4', 'Mujeeb', 4, 18),
    ];

void main() {
  test('a three-way tie on rank 1 resolves to the viewer by id', () {
    final FixtureLeaderboardEntryDto? me = findMyFixtureEntry(
      entries: _tiedBoard,
      myPredictions: <FixturePredictionDto>[_prediction('p-3', 's-9')],
      seasonId: 's-9',
    );
    expect(me?.participantId, 'p-3');
    expect(me?.totalPoints, 21);
    expect(me?.rank, 1);
  });

  test('a prediction from another season is ignored; name is the fallback', () {
    final FixtureLeaderboardEntryDto? me = findMyFixtureEntry(
      entries: _tiedBoard,
      myPredictions: <FixturePredictionDto>[_prediction('p-1', 's-8')],
      seasonId: 's-9',
      displayName: ' Mujeeb ',
    );
    expect(me?.participantId, 'p-4');
  });

  test('no id and no name match gives null', () {
    expect(
      findMyFixtureEntry(
        entries: _tiedBoard,
        myPredictions: const <FixturePredictionDto>[],
        seasonId: 's-9',
        displayName: 'Nobody',
      ),
      isNull,
    );
  });
}
