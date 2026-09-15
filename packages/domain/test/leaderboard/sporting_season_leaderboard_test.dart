import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

SportingSeasonStanding _standing(String id, int points) {
  final result = SportingSeasonStanding.projected(
    userId: UserId(id),
    displayName: 'user-$id',
    totalPoints: points,
    fixturesScored: 4,
    exactCount: 1,
    decidedCount: 3,
    monthsPlayed: 2,
  );
  return (result as Ok<SportingSeasonStanding>).value;
}

void main() {
  const a = '00000000-0000-0000-0000-00000000000a';
  const b = '00000000-0000-0000-0000-00000000000b';
  const c = '00000000-0000-0000-0000-00000000000c';

  group('SportingSeason.containing', () {
    test('September opens a new season', () {
      final season = SportingSeason.containing(DateTime.utc(2026, 9, 1));
      expect(season.startYear, 2026);
      expect(season.firstMonthKey, 202609);
      expect(season.lastMonthKey, 202708);
      expect(season.label, '2026/2027');
    });

    test('August still belongs to the season that began last September', () {
      final season = SportingSeason.containing(DateTime.utc(2027, 8, 31, 23));
      expect(season.startYear, 2026);
    });

    test('January belongs to the season that began last September', () {
      final season = SportingSeason.containing(DateTime.utc(2027, 1, 15));
      expect(season, SportingSeason.containing(DateTime.utc(2026, 10, 1)));
    });
  });

  group('SportingSeasonLeaderboard.rank', () {
    final season = SportingSeason.containing(DateTime.utc(2026, 9, 20));

    test('orders by points and shares ranks on ties (1-1-3)', () {
      final result = SportingSeasonLeaderboard.rank(
        season: season,
        standings: [_standing(c, 10), _standing(b, 30), _standing(a, 30)],
      );
      final board = (result as Ok<SportingSeasonLeaderboard>).value;
      expect(board.entries.map((e) => e.userId.value), [a, b, c]);
      expect(board.entries.map((e) => e.rank), [1, 1, 3]);
    });

    test('an empty season is a legitimate empty board', () {
      final result = SportingSeasonLeaderboard.rank(
        season: season,
        standings: const [],
      );
      expect((result as Ok<SportingSeasonLeaderboard>).value.entries, isEmpty);
    });

    test('a user listed twice is refused', () {
      final result = SportingSeasonLeaderboard.rank(
        season: season,
        standings: [_standing(a, 1), _standing(a, 2)],
      );
      expect(result, isA<Err<SportingSeasonLeaderboard>>());
    });
  });

  test('exact calls cannot outnumber decided fixtures', () {
    final result = SportingSeasonStanding.projected(
      userId: const UserId(a),
      displayName: 'x',
      totalPoints: 3,
      fixturesScored: 1,
      exactCount: 2,
      decidedCount: 1,
      monthsPlayed: 1,
    );
    expect(result, isA<Err<SportingSeasonStanding>>());
  });
}
