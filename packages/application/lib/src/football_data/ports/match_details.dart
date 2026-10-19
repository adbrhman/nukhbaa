import 'package:shared/shared.dart';

/// What happened at one moment of a match, as the details page shows it.
enum MatchEventKind {
  /// A goal from open play or a set piece.
  goal,

  /// A goal from the penalty spot.
  penaltyGoal,

  /// An own goal.
  ownGoal,

  /// A penalty that was not scored.
  missedPenalty,

  /// A yellow card.
  yellowCard,

  /// A second yellow, and so a sending-off.
  secondYellow,

  /// A straight red card.
  redCard,

  /// A goal the VAR ruled out.
  varGoalCancelled,

  /// A substitution.
  substitution,

  /// Anything else the provider reports (a VAR check that changed nothing,
  /// a penalty awarded on review...): kept, not shown.
  other;

  /// The wire name (`penalty_goal`, `var_goal_cancelled`...).
  String get wire => switch (this) {
    MatchEventKind.goal => 'goal',
    MatchEventKind.penaltyGoal => 'penalty_goal',
    MatchEventKind.ownGoal => 'own_goal',
    MatchEventKind.missedPenalty => 'missed_penalty',
    MatchEventKind.yellowCard => 'yellow_card',
    MatchEventKind.secondYellow => 'second_yellow',
    MatchEventKind.redCard => 'red_card',
    MatchEventKind.varGoalCancelled => 'var_goal_cancelled',
    MatchEventKind.substitution => 'substitution',
    MatchEventKind.other => 'other',
  };

  /// The kind named [wire]; [other] for a name not known here.
  static MatchEventKind fromWire(String wire) {
    for (final kind in MatchEventKind.values) {
      if (kind.wire == wire) {
        return kind;
      }
    }
    return MatchEventKind.other;
  }

  /// Whether it changes the score: an own goal counts for the other side.
  bool get scores =>
      this == MatchEventKind.goal ||
      this == MatchEventKind.penaltyGoal ||
      this == MatchEventKind.ownGoal;
}

/// One event of a match.
final class MatchEvent {
  /// Creates the event.
  const MatchEvent({
    required this.minute,
    required this.kind,
    required this.home,
    this.player,
    this.assist,
    this.detail,
  });

  /// The clock as the provider writes it: `"14"`, `"45+4"`, `"90+7"`.
  final String minute;

  /// What happened.
  final MatchEventKind kind;

  /// Whether it belongs to the home side (the side of the player named).
  final bool home;

  /// The player it is about, when named.
  final String? player;

  /// The assisting player of a goal, or the player brought on for a
  /// substitution, when named.
  final String? assist;

  /// The provider's own name for the event (`"VAR Goal Cancelled"`), kept
  /// for an event shown as [MatchEventKind.other].
  final String? detail;

  /// The minute as a number for ordering: `"45+4"` is 45.04.
  double get order {
    final parts = minute.split('+');
    final base = int.tryParse(parts.first.trim()) ?? 0;
    final added = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return base + added / 100;
  }
}

/// A match's story as the details page shows it: its events, the score at
/// half time, where it was played. Display only: it never scores anything.
final class MatchDetails {
  /// Creates the details.
  const MatchDetails({
    required this.fixtureId,
    required this.found,
    required this.fetchedAt,
    this.source = '',
    this.externalMatchId,
    this.events = const <MatchEvent>[],
    this.halfTimeHome,
    this.halfTimeAway,
    this.venue,
    this.round,
    this.referee,
  });

  /// A fixture the provider has no match for: asked once, not again.
  factory MatchDetails.notFound({
    required String fixtureId,
    required String source,
    required DateTime fetchedAt,
  }) => MatchDetails(
    fixtureId: fixtureId,
    found: false,
    source: source,
    fetchedAt: fetchedAt,
  );

  /// The app's fixture id.
  final String fixtureId;

  /// Whether the provider had the match; nothing else is set when not.
  final bool found;

  /// The provider asked.
  final String source;

  /// The provider's match id, when found.
  final String? externalMatchId;

  /// The events, in the provider's order.
  final List<MatchEvent> events;

  /// Home goals at half time, when known.
  final int? halfTimeHome;

  /// Away goals at half time, when known.
  final int? halfTimeAway;

  /// The ground.
  final String? venue;

  /// The round (`"Regular Season - 8"`).
  final String? round;

  /// The referee.
  final String? referee;

  /// When it was read from the provider, UTC.
  final DateTime fetchedAt;

  /// The score at half time worked out from the goals: those up to the 45th
  /// minute and its added time. Null when an own goal falls in the first
  /// half, since providers differ on whose side they file it under.
  static (int, int)? halfTimeFromEvents(List<MatchEvent> events) {
    var home = 0;
    var away = 0;
    for (final event in events) {
      if (!event.kind.scores) {
        continue;
      }
      final base = int.tryParse(event.minute.split('+').first.trim());
      if (base == null) {
        return null;
      }
      if (base > 45) {
        continue;
      }
      if (event.kind == MatchEventKind.ownGoal) {
        return null;
      }
      if (event.home) {
        home++;
      } else {
        away++;
      }
    }
    return (home, away);
  }
}

/// A finished match the details are still to be read for.
final class PendingMatchDetails {
  /// Creates the entry.
  const PendingMatchDetails({
    required this.fixtureId,
    required this.kickoffAt,
    required this.leagueName,
    required this.homeGoals,
    required this.awayGoals,
    this.externalMatchId,
  });

  /// The app's fixture id.
  final String fixtureId;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// The name of the league the fixture is filed under.
  final String leagueName;

  /// The recorded result.
  final int homeGoals;

  /// The recorded result.
  final int awayGoals;

  /// The details provider's own match id when the fixture came from it
  /// (the Roshan League, the Europa League); null otherwise.
  final String? externalMatchId;
}

/// Where match details are kept.
abstract interface class MatchDetailsStore {
  /// Fixtures with a recorded result, a league, a kickoff from
  /// [kickedOffFrom] up to (not including) [kickedOffBefore] and no details
  /// yet, earliest first. [source] names the provider whose match ids are
  /// looked up.
  Future<Result<List<PendingMatchDetails>>> pending({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  });

  /// Stores [details], replacing what the fixture had.
  Future<Result<void>> save(MatchDetails details);

  /// The details of [fixtureId]; null when none were read yet.
  Future<Result<MatchDetails?>> find(String fixtureId);
}

/// Reads one match's details from a provider.
abstract interface class MatchDetailsSource {
  /// The provider's name for [MatchDetails.source].
  String get source;

  /// The details of the provider's match [externalMatchId], for the app's
  /// [fixtureId]; null when the provider says the match is not over yet.
  /// Returns an error with code `football_data.provider_quota` when it is
  /// keeping the rest of its daily requests.
  Future<Result<MatchDetails?>> details({
    required String externalMatchId,
    required String fixtureId,
  });
}
