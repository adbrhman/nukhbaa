import 'package:application/application.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:test/test.dart';

void main() {
  test('the board forgets scores that were not refreshed', () {
    var clock = DateTime.utc(2026, 9, 19, 15);
    final board = InMemoryLiveScoreBoard(now: () => clock)
      ..put({
        'f1': LiveScore(
          homeGoals: 1,
          awayGoals: 0,
          minute: 30,
          finished: false,
          updatedAt: clock,
        ),
      });

    expect(board.read(['f1', 'f2']).keys, ['f1']);
    clock = clock.add(const Duration(minutes: 16));
    expect(board.read(['f1']), isEmpty);
  });

  test('football-data.org: a match in play carries its running score', () {
    final match = FootballDataOrgProvider.parseMatch({
      'id': 7,
      'utcDate': '2026-09-19T14:00:00Z',
      'status': 'IN_PLAY',
      'minute': 67,
      'homeTeam': {'id': 57, 'name': 'Arsenal FC'},
      'awayTeam': {'id': 61, 'name': 'Chelsea FC'},
      'score': {
        'duration': 'REGULAR',
        'fullTime': {'home': 2, 'away': 1},
      },
    }, 'PL')!;
    expect(match.status, ProviderMatchStatus.live);
    expect((match.currentHomeGoals, match.currentAwayGoals), (2, 1));
    expect(match.minute, 67);
    expect(match.homeGoals, isNull);
  });

  test('Highlightly: a match in play carries its running score', () {
    final match = HighlightlyFootballDataProvider.parseMatch({
      'id': 8,
      'date': '2026-09-19T14:00:00.000Z',
      'league': {'id': 262041},
      'homeTeam': {'id': 2495916, 'name': 'Al-Hilal Saudi'},
      'awayTeam': {'id': 2501873, 'name': 'Al-Nassr'},
      'state': {
        'description': 'Second half',
        'clock': 71,
        'score': {'current': '1 - 1'},
      },
    })!;
    expect(match.status, ProviderMatchStatus.live);
    expect((match.currentHomeGoals, match.currentAwayGoals), (1, 1));
    expect(match.minute, 71);
  });
}
