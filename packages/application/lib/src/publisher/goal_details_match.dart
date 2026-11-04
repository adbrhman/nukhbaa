import 'package:application/src/football_data/ports/match_details.dart';
import 'package:domain/domain.dart';

/// What the provider said about one goal.
final class GoalDetails {
  /// Creates the details.
  const GoalDetails({
    required this.minuteLabel,
    required this.penalty,
    required this.ownGoal,
    this.scorer,
  });

  /// The player, when named.
  final String? scorer;

  /// The clock as the provider writes it.
  final String minuteLabel;

  /// From the spot.
  final bool penalty;

  /// An own goal.
  final bool ownGoal;
}

/// Finds a goal among a provider's events (pure).
///
/// The goal is the scoring event, in clock order, after which the score is
/// the goal's own: the third home goal is the event that makes the home
/// side's count three. Providers differ on the side they file an own goal
/// under (see `MatchDetails.halfTimeFromEvents`), so both readings are
/// tried, the usual one first.
final class GoalDetailsMatch {
  const GoalDetailsMatch._();

  /// The details of [step] in [events]; null when no reading of the
  /// events reaches its score with its side.
  static GoalDetails? find(GoalStep step, List<MatchEvent> events) {
    final scoring = <MatchEvent>[
      for (final event in events)
        if (event.kind.scores) event,
    ]..sort((a, b) => a.order.compareTo(b.order));
    for (final ownGoalForOther in const <bool>[true, false]) {
      var home = 0;
      var away = 0;
      for (final event in scoring) {
        final forHome = event.kind == MatchEventKind.ownGoal && ownGoalForOther
            ? !event.home
            : event.home;
        if (forHome) {
          home++;
        } else {
          away++;
        }
        if (forHome == step.home && ScoreLine(home, away) == step.after) {
          return GoalDetails(
            scorer: event.player,
            minuteLabel: event.minute,
            penalty: event.kind == MatchEventKind.penaltyGoal,
            ownGoal: event.kind == MatchEventKind.ownGoal,
          );
        }
      }
    }
    return null;
  }
}
