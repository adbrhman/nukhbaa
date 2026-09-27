import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// Invitation points break a points tie (decided 2026-09-27): the month's on
// the monthly board, the season's on the sporting-season board. Then exact
// scorelines. Level on all three means the same rank. They never add to
// the points. The daily snapshot SQL (migration 0074) is tested with the
// same four players in supabase/tests/0074_referral_tie_break_test.sql.

const _season = SeasonId('11111111-1111-1111-1111-111111111111');
const _ahmad = 'aaaaaaaa-0000-0000-0000-000000000001';
const _khaled = 'aaaaaaaa-0000-0000-0000-000000000002';
const _sami = 'aaaaaaaa-0000-0000-0000-000000000003';
const _omar = 'aaaaaaaa-0000-0000-0000-000000000004';
const _names = {
  _ahmad: 'Ahmad',
  _khaled: 'Khaled',
  _sami: 'Sami',
  _omar: 'Omar',
};

ParticipantFixtureTotals _month(String id, int exact, int referrals) =>
    (ParticipantFixtureTotals.of(
              participantId: ParticipantId(id),
              totalPoints: 120,
              fixturesScored: 40,
              exactCount: exact,
              decidedCount: 38,
              referralPoints: referrals,
            )
            as Ok<ParticipantFixtureTotals>)
        .value;

SportingSeasonStanding _seasonLine(String id, int exact, int referrals) =>
    (SportingSeasonStanding.projected(
              userId: UserId(id),
              displayName: _names[id]!,
              totalPoints: 900,
              fixturesScored: 300,
              exactCount: exact,
              decidedCount: 290,
              monthsPlayed: 9,
              referralPoints: referrals,
            )
            as Ok<SportingSeasonStanding>)
        .value;

void main() {
  group('the monthly board', () {
    FixtureLeaderboard board({bool breakTiesByReferrals = true}) =>
        (FixtureLeaderboard.rankTotals(
                  seasonId: _season,
                  displayNames: _names,
                  breakTiesByReferrals: breakTiesByReferrals,
                  totals: [
                    _month(_omar, 10, 0),
                    _month(_khaled, 10, 0),
                    _month(_sami, 12, 0),
                    _month(_ahmad, 10, 20),
                  ],
                )
                as Ok<FixtureLeaderboard>)
            .value;

    test('120 each: the most invitation points is first', () {
      final entries = board().entries;
      expect(entries.first.displayName, 'Ahmad');
      expect(entries.first.rank, 1);
      expect(entries.first.referralPoints, 20);
      expect(entries.first.totalPoints, 120);
    });

    test('no invitations: more exact scorelines ranks higher', () {
      final entries = board().entries;
      expect(entries[1].displayName, 'Sami');
      expect(entries[1].rank, 2);
    });

    test('level on points, invitations and exact calls: the same rank', () {
      final entries = board().entries;
      expect(entries.map((e) => e.rank).toList(), [1, 2, 3, 3]);
      expect(entries.sublist(2).map((e) => e.displayName).toSet(), {
        'Khaled',
        'Omar',
      });
    });

    test('invitation points are never added to the points', () {
      for (final entry in board().entries) {
        expect(entry.totalPoints, 120);
      }
    });

    test('a day board ranks without invitation points', () {
      final entries = board(breakTiesByReferrals: false).entries;
      expect(entries.first.displayName, 'Sami');
      expect(entries.map((e) => e.referralPoints).toSet(), {0});
      expect(entries.map((e) => e.rank).toList(), [1, 2, 2, 2]);
    });
  });

  group('the sporting-season board', () {
    test('the season total of invitation points breaks the tie', () {
      final result = SportingSeasonLeaderboard.rank(
        season: SportingSeason.containing(DateTime.utc(2027, 8, 31)),
        standings: [
          _seasonLine(_khaled, 80, 5),
          _seasonLine(_ahmad, 80, 21),
          _seasonLine(_sami, 95, 5),
          _seasonLine(_omar, 80, 5),
        ],
      );
      final entries = (result as Ok<SportingSeasonLeaderboard>).value.entries;
      expect(entries.map((e) => e.displayName).first, 'Ahmad');
      expect(entries.map((e) => e.rank).toList(), [1, 2, 3, 3]);
      expect(entries[1].displayName, 'Sami');
      expect(entries.first.totalPoints, 900);
    });

    test('negative invitation points are refused', () {
      final result = SportingSeasonStanding.projected(
        userId: const UserId(_ahmad),
        displayName: 'Ahmad',
        totalPoints: 1,
        fixturesScored: 1,
        exactCount: 0,
        decidedCount: 1,
        monthsPlayed: 1,
        referralPoints: -1,
      );
      expect(result, isA<Err<SportingSeasonStanding>>());
    });
  });
}
