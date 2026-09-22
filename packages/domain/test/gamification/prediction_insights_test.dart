import 'package:domain/domain.dart';
import 'package:test/test.dart';

// Wednesday 2026-09-23 in Riyadh: this week opened on Monday the 21st,
// last week on Monday the 14th, the month on the 1st.
final DateTime _today = DateTime.utc(2026, 9, 23);

PredictionOutcome _o(
  DateTime kickoff,
  PredictionGrade grade, {
  int points = 0,
  bool followed = false,
  String? league = 'L1',
}) => PredictionOutcome(
  fixtureId: kickoff.toIso8601String(),
  kickoffAt: kickoff,
  homeTeam: 'home',
  awayTeam: 'away',
  grade: grade,
  points: points,
  followed: followed,
  leagueName: league,
);

void main() {
  group('AccuracyTally', () {
    test('nothing decided has no percent, not zero', () {
      expect(AccuracyTally.empty.percent, isNull);
    });

    test('exact counts as correct', () {
      final tally = AccuracyTally.of([
        _o(DateTime.utc(2026, 9, 2), PredictionGrade.exact),
        _o(DateTime.utc(2026, 9, 3), PredictionGrade.correct),
        _o(DateTime.utc(2026, 9, 4), PredictionGrade.incorrect),
        _o(DateTime.utc(2026, 9, 5), PredictionGrade.incorrect),
      ]);

      expect(tally.decided, 4);
      expect(tally.correct, 2);
      expect(tally.exact, 1);
      expect(tally.percent, 50);
    });
  });

  group('PredictionInsights.compute', () {
    test('the month excludes last month', () {
      final insights = PredictionInsights.compute(
        outcomes: [
          _o(DateTime.utc(2026, 8, 30), PredictionGrade.correct),
          _o(DateTime.utc(2026, 9, 10), PredictionGrade.incorrect),
        ],
        today: _today,
      );

      expect(insights.month.decided, 1);
      expect(insights.month.percent, 0);
    });

    test('last week is recapped with its best prediction', () {
      final insights = PredictionInsights.compute(
        outcomes: [
          _o(DateTime.utc(2026, 9, 15, 18), PredictionGrade.correct, points: 1),
          _o(DateTime.utc(2026, 9, 16, 18), PredictionGrade.exact, points: 3),
          _o(DateTime.utc(2026, 9, 22, 18), PredictionGrade.exact, points: 3),
        ],
        today: _today,
      );

      final recap = insights.lastWeek!;
      expect(recap.weekStart, DateTime.utc(2026, 9, 14));
      expect(recap.tally.decided, 2);
      expect(recap.points, 4);
      expect(recap.best!.grade, PredictionGrade.exact);
      expect(insights.weeks, hasLength(PredictionInsights.weekCount));
      expect(insights.weeks.last.weekStart, DateTime.utc(2026, 9, 21));
      expect(insights.weeks.last.tally.decided, 1);
    });

    test('a quiet last week has no recap', () {
      final insights = PredictionInsights.compute(
        outcomes: [_o(DateTime.utc(2026, 9, 22), PredictionGrade.correct)],
        today: _today,
      );

      expect(insights.lastWeek, isNull);
    });

    test('best and worst league need a sample and a difference', () {
      final outcomes = <PredictionOutcome>[
        for (var i = 0; i < 5; i++)
          _o(
            DateTime.utc(2026, 9, 1 + i),
            PredictionGrade.correct,
            league: 'A',
          ),
        for (var i = 0; i < 5; i++)
          _o(
            DateTime.utc(2026, 9, 10 + i),
            PredictionGrade.incorrect,
            league: 'B',
          ),
        _o(DateTime.utc(2026, 9, 20), PredictionGrade.correct, league: 'C'),
      ];

      final insights = PredictionInsights.compute(
        outcomes: outcomes,
        today: _today,
      );

      expect(insights.bestLeague, 'A');
      expect(insights.worstLeague, 'B');
      expect(insights.leagues.map((l) => l.name), containsAll(['A', 'B', 'C']));
    });

    test('the followed-team bias needs both samples', () {
      final few = PredictionInsights.compute(
        outcomes: [
          _o(DateTime.utc(2026, 9, 2), PredictionGrade.correct, followed: true),
          _o(DateTime.utc(2026, 9, 3), PredictionGrade.correct),
        ],
        today: _today,
      );
      expect(few.followed, isNull);

      final enough = PredictionInsights.compute(
        outcomes: [
          for (var i = 0; i < 3; i++)
            _o(
              DateTime.utc(2026, 9, 2 + i),
              PredictionGrade.incorrect,
              followed: true,
            ),
          for (var i = 0; i < 3; i++)
            _o(DateTime.utc(2026, 9, 8 + i), PredictionGrade.correct),
        ],
        today: _today,
      );
      expect(enough.followed!.percent, 0);
      expect(enough.others!.percent, 100);
    });

    test('the longest right run follows kickoff order', () {
      final insights = PredictionInsights.compute(
        outcomes: [
          _o(DateTime.utc(2026, 9, 5), PredictionGrade.correct),
          _o(DateTime.utc(2026, 9, 1), PredictionGrade.correct),
          _o(DateTime.utc(2026, 9, 3), PredictionGrade.incorrect),
          _o(DateTime.utc(2026, 9, 6), PredictionGrade.exact),
        ],
        today: _today,
      );

      expect(insights.longestCorrectRun, 2);
    });

    test('the window reaches back to the oldest week or the month', () {
      expect(PredictionInsights.windowStart(_today), DateTime.utc(2026, 8, 3));
    });
  });
}
