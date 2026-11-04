/// A score at one moment of a match, home goals first.
final class ScoreLine {
  /// Creates the score. Goals are never negative.
  const ScoreLine(this.home, this.away)
    : assert(home >= 0, 'home goals are never negative'),
      assert(away >= 0, 'away goals are never negative');

  /// Before kickoff.
  static const ScoreLine nil = ScoreLine(0, 0);

  /// Home goals.
  final int home;

  /// Away goals.
  final int away;

  /// The goals [home] side has when [forHome], else the away side's.
  int of({required bool forHome}) => forHome ? home : away;

  /// Whether [home] leads.
  bool get homeLeads => home > away;

  /// Whether the away side leads.
  bool get awayLeads => away > home;

  /// Whether the sides are level.
  bool get level => home == away;

  @override
  bool operator ==(Object other) =>
      other is ScoreLine && other.home == home && other.away == away;

  @override
  int get hashCode => Object.hash(home, away);

  @override
  String toString() => '$home-$away';
}

/// One goal as the publisher sees it: the side that scored, the score just
/// before it and just after it.
final class GoalStep {
  /// Creates the step.
  const GoalStep({required this.home, required this.before});

  /// Whether the home side scored (an own goal counts for the side it was
  /// scored for, as the score does).
  final bool home;

  /// The score just before this goal.
  final ScoreLine before;

  /// The score just after this goal.
  ScoreLine get after => home
      ? ScoreLine(before.home + 1, before.away)
      : ScoreLine(before.home, before.away + 1);

  /// Which goal of its side this is (1 for the side's first goal). With
  /// [home], the key that names a goal within a match: the third home goal
  /// stays the third home goal whatever the other side does.
  int get ordinal => after.of(forHome: home);

  /// The key of this goal within its match: `h3` is the third home goal.
  String get key => '${home ? 'h' : 'a'}$ordinal';

  @override
  bool operator ==(Object other) =>
      other is GoalStep && other.home == home && other.before == before;

  @override
  int get hashCode => Object.hash(home, before);

  @override
  String toString() => '$key ($before -> $after)';
}

/// What changed between the score the publisher last knew and the one a feed
/// now shows.
final class ScoreChange {
  /// Creates the change.
  const ScoreChange({
    required this.added,
    required this.withdrawn,
    required this.bothSidesScored,
  });

  /// Nothing changed.
  static const ScoreChange none = ScoreChange(
    added: <GoalStep>[],
    withdrawn: <String>[],
    bothSidesScored: false,
  );

  /// The new goals, in the order the publisher assumes they were scored.
  final List<GoalStep> added;

  /// The keys ([GoalStep.key]) of goals the feed no longer counts: a goal
  /// ruled out after the feed reported it (the VAR), or a feed's mistake.
  final List<String> withdrawn;

  /// Both sides scored between two reads, so the order of [added] is a
  /// guess (home goals first) until the scorers' minutes are known.
  final bool bothSidesScored;

  /// Whether anything changed.
  bool get isEmpty => added.isEmpty && withdrawn.isEmpty;
}

/// The publisher's reading of a running score (pure, no clock).
///
/// The feed reports only the score, every two minutes; a goal is what makes a
/// side's count go up, and a count that goes down withdraws that side's
/// latest goals. A withdrawn goal keeps its key, so a goal the VAR rules out
/// before it is confirmed is never posted, and one ruled out after is
/// corrected.
final class GoalWatch {
  const GoalWatch._();

  /// The change from [known] to [seen].
  ///
  /// When one side's count went up and the other's down in the same read,
  /// both are reported: the lost goals withdrawn, the new ones added on the
  /// score as it stands without them.
  static ScoreChange diff(ScoreLine known, ScoreLine seen) {
    if (known == seen) {
      return ScoreChange.none;
    }
    final withdrawn = <String>[
      for (var n = known.home; n > seen.home; n--) 'h$n',
      for (var n = known.away; n > seen.away; n--) 'a$n',
    ];
    // The score with the withdrawn goals taken off, from which new goals
    // are counted.
    var running = ScoreLine(
      known.home < seen.home ? known.home : seen.home,
      known.away < seen.away ? known.away : seen.away,
    );
    final added = <GoalStep>[];
    while (running.home < seen.home) {
      final step = GoalStep(home: true, before: running);
      added.add(step);
      running = step.after;
    }
    final homeGoals = added.length;
    while (running.away < seen.away) {
      final step = GoalStep(home: false, before: running);
      added.add(step);
      running = step.after;
    }
    final awayGoals = added.length - homeGoals;
    return ScoreChange(
      added: added,
      withdrawn: withdrawn,
      bothSidesScored: homeGoals > 0 && awayGoals > 0,
    );
  }

  /// Whether a goal [step] is still counted by a feed that shows [seen].
  static bool stillCounted(GoalStep step, ScoreLine seen) =>
      seen.of(forHome: step.home) >= step.ordinal;

  /// Whether [step], first seen at [firstSeenAt], has stood for [hold] at
  /// [now] on a feed that still shows [seen].
  static bool confirmed({
    required GoalStep step,
    required ScoreLine seen,
    required DateTime firstSeenAt,
    required DateTime now,
    required Duration hold,
  }) => stillCounted(step, seen) && now.difference(firstSeenAt) >= hold;
}
