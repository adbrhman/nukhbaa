import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

ParticipantFixtureScore _score({
  required String fixtureId,
  required String participantId,
  required int points,
  FixtureScoreGrade grade = FixtureScoreGrade.exactScoreline,
}) {
  final fixture = FixtureRef(fixtureId);
  return ParticipantFixtureScore.fromStored(
    fixture: fixture,
    participantId: ParticipantId(participantId),
    rulesetVersion: 1,
    result: FixtureScoreResult(fixture: fixture, grade: grade, points: points),
  );
}

void main() {
  final seasonId = const SeasonId('11111111-1111-1111-1111-111111111111');

  group('FixtureLeaderboard.rank', () {
    test(
      'empty scores yields an empty board (legitimate live/partial state)',
      () {
        final result = FixtureLeaderboard.rank(seasonId: seasonId, scores: []);
        expect(result, isA<Ok<FixtureLeaderboard>>());
        final board = (result as Ok<FixtureLeaderboard>).value;
        expect(board.entries, isEmpty);
        expect(board.size, 0);
      },
    );

    test('sums multiple fixture scores per participant (live aggregation)', () {
      final scores = [
        _score(
          fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          points: 10,
        ),
        _score(
          fixtureId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          points: 5,
        ),
      ];
      final result = FixtureLeaderboard.rank(
        seasonId: seasonId,
        scores: scores,
      );
      final board = (result as Ok<FixtureLeaderboard>).value;
      expect(board.entries, hasLength(1));
      expect(board.entries.first.totalPoints, 15);
      expect(board.entries.first.fixturesScored, 2);
      expect(board.entries.first.rank, 1);
    });

    test(
      'a participant with fewer fixtures scored still ranks (partial/live)',
      () {
        final scores = [
          _score(
            fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            points: 10,
          ),
          _score(
            fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            participantId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            points: 3,
          ),
        ];
        final result = FixtureLeaderboard.rank(
          seasonId: seasonId,
          scores: scores,
        );
        final board = (result as Ok<FixtureLeaderboard>).value;
        expect(board.entries, hasLength(2));
        expect(board.entries.first.totalPoints, 10);
        expect(board.entries.first.fixturesScored, 1);
        expect(board.entries.last.fixturesScored, 1);
      },
    );

    test('standard-competition (1224) ranking on a tie', () {
      final scores = [
        _score(
          fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          participantId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          points: 10,
        ),
        _score(
          fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          participantId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
          points: 10,
        ),
        _score(
          fixtureId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          participantId: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
          points: 5,
        ),
      ];
      final result = FixtureLeaderboard.rank(
        seasonId: seasonId,
        scores: scores,
      );
      final board = (result as Ok<FixtureLeaderboard>).value;
      expect(board.entries[0].rank, 1);
      expect(board.entries[1].rank, 1);
      expect(board.entries[2].rank, 3);
    });
  });
}
