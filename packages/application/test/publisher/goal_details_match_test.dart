import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  const events = <MatchEvent>[
    MatchEvent(
      minute: '12',
      kind: MatchEventKind.goal,
      home: true,
      player: 'A',
    ),
    MatchEvent(
      minute: '30',
      kind: MatchEventKind.yellowCard,
      home: false,
      player: 'X',
    ),
    MatchEvent(
      minute: '45+2',
      kind: MatchEventKind.penaltyGoal,
      home: false,
      player: 'B',
    ),
    MatchEvent(
      minute: '51',
      kind: MatchEventKind.varGoalCancelled,
      home: true,
      player: 'C',
    ),
    MatchEvent(
      minute: '70',
      kind: MatchEventKind.goal,
      home: true,
      player: 'D',
    ),
  ];

  test('finds each goal by the score it made', () {
    final first = GoalDetailsMatch.find(
      const GoalStep(home: true, before: ScoreLine.nil),
      events,
    );
    final penalty = GoalDetailsMatch.find(
      const GoalStep(home: false, before: ScoreLine(1, 0)),
      events,
    );
    final third = GoalDetailsMatch.find(
      const GoalStep(home: true, before: ScoreLine(1, 1)),
      events,
    );

    expect(first?.scorer, 'A');
    expect(penalty?.scorer, 'B');
    expect(penalty?.penalty, isTrue);
    expect(penalty?.minuteLabel, '45+2');
    expect(third?.scorer, 'D');
  });

  test('a goal ruled out never counts in the score', () {
    final second = GoalDetailsMatch.find(
      const GoalStep(home: true, before: ScoreLine(1, 1)),
      events,
    );

    expect(second?.minuteLabel, '70');
  });

  test('an own goal is found whichever side the provider filed it under', () {
    // Filed under the scorer's own side (the away player who put it in his
    // net), credited to the home side.
    const asFiled = <MatchEvent>[
      MatchEvent(
        minute: '20',
        kind: MatchEventKind.ownGoal,
        home: false,
        player: 'E',
      ),
    ];
    // Filed under the side it counts for.
    const asCounted = <MatchEvent>[
      MatchEvent(
        minute: '20',
        kind: MatchEventKind.ownGoal,
        home: true,
        player: 'E',
      ),
    ];
    const step = GoalStep(home: true, before: ScoreLine.nil);

    expect(GoalDetailsMatch.find(step, asFiled)?.ownGoal, isTrue);
    expect(GoalDetailsMatch.find(step, asCounted)?.scorer, 'E');
  });

  test('a goal the events do not reach is not found', () {
    expect(
      GoalDetailsMatch.find(
        const GoalStep(home: false, before: ScoreLine(2, 1)),
        events,
      ),
      isNull,
    );
  });

  test('the events are read in clock order, whatever the provider order', () {
    const shuffled = <MatchEvent>[
      MatchEvent(
        minute: '80',
        kind: MatchEventKind.goal,
        home: true,
        player: 'Late',
      ),
      MatchEvent(
        minute: '5',
        kind: MatchEventKind.goal,
        home: true,
        player: 'Early',
      ),
    ];

    expect(
      GoalDetailsMatch.find(
        const GoalStep(home: true, before: ScoreLine.nil),
        shuffled,
      )?.scorer,
      'Early',
    );
  });
}
