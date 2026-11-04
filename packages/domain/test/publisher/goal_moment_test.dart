import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  GoalMoment moment(int home, int away, {required bool forHome, int? minute}) =>
      GoalMoment.of(
        GoalStep(home: forHome, before: ScoreLine(home, away)),
        minute: minute,
      );

  group('GoalMoment.of', () {
    test('the first goal opens the match', () {
      expect(moment(0, 0, forHome: false, minute: 12), GoalMoment.opener);
    });

    test('a goal that levels is the equaliser', () {
      expect(moment(1, 0, forHome: false, minute: 60), GoalMoment.equaliser);
      expect(moment(2, 3, forHome: true, minute: 70), GoalMoment.equaliser);
    });

    test('a goal from level puts its side ahead', () {
      expect(moment(1, 1, forHome: true, minute: 50), GoalMoment.goAhead);
    });

    test('a goal on top of a lead extends it', () {
      expect(moment(1, 0, forHome: true, minute: 30), GoalMoment.extendsLead);
    });

    test('a goal that narrows a deficit reduces it', () {
      expect(
        moment(0, 2, forHome: true, minute: 30),
        GoalMoment.reducesDeficit,
      );
    });

    test('from the 85th minute a levelling or leading goal is a late one', () {
      expect(
        moment(1, 0, forHome: false, minute: 85),
        GoalMoment.lateEqualiser,
      );
      expect(moment(2, 2, forHome: false, minute: 90), GoalMoment.lateWinner);
      expect(moment(0, 0, forHome: true, minute: 88), GoalMoment.lateWinner);
    });

    test('a late goal that only extends a lead is not a late winner', () {
      expect(moment(2, 0, forHome: true, minute: 89), GoalMoment.extendsLead);
    });

    test('an unknown minute is never late', () {
      expect(moment(1, 1, forHome: true), GoalMoment.goAhead);
    });
  });

  group('GoalMoment.minuteOf', () {
    test('reads the minute before any added time', () {
      expect(GoalMoment.minuteOf('45+2'), 45);
      expect(GoalMoment.minuteOf('90'), 90);
      expect(GoalMoment.minuteOf(' 7 '), 7);
    });

    test('is null for no label or a label that is not a minute', () {
      expect(GoalMoment.minuteOf(null), isNull);
      expect(GoalMoment.minuteOf('HT'), isNull);
    });
  });

  test('only goals that open, level or turn a match are key', () {
    expect(
      <GoalMoment>[
        for (final value in GoalMoment.values)
          if (value.key) value,
      ],
      <GoalMoment>[
        GoalMoment.opener,
        GoalMoment.equaliser,
        GoalMoment.goAhead,
        GoalMoment.lateEqualiser,
        GoalMoment.lateWinner,
      ],
    );
  });

  test('every moment reads back from its stored name', () {
    for (final value in GoalMoment.values) {
      expect(GoalMoment.fromWire(value.wire), value);
    }
    expect(GoalMoment.fromWire('own_goal'), isNull);
  });
}
