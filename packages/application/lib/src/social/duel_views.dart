import 'package:domain/domain.dart';

/// How a challenge looks to a player at a given instant.
///
/// Migration 0090 stores only open, cancelled and declined. Full and expired
/// are derived here from the accepted count and the kickoff, never stored.
enum DuelChallengeState {
  /// Still accepting opponents.
  open,

  /// Every seat is taken.
  full,

  /// The fixture kicked off before the challenge filled.
  expired,

  /// The challenger closed it.
  cancelled,

  /// The private target refused it.
  declined;

  /// Stable wire token.
  String get wireValue => switch (this) {
    DuelChallengeState.open => 'open',
    DuelChallengeState.full => 'full',
    DuelChallengeState.expired => 'expired',
    DuelChallengeState.cancelled => 'cancelled',
    DuelChallengeState.declined => 'declined',
  };
}

/// Where an accepted duel stands, derived from the kickoff and the scores.
enum DuelState {
  /// Before kickoff: both predictions can still change.
  upcoming,

  /// Kicked off, no final grade for both sides yet.
  live,

  /// Both sides hold a final grade.
  settled;

  /// Stable wire token.
  String get wireValue => switch (this) {
    DuelState.upcoming => 'upcoming',
    DuelState.live => 'live',
    DuelState.settled => 'settled',
  };
}

/// The result of a settled duel for the caller.
enum DuelOutcome {
  /// The caller scored more points.
  won,

  /// The opponent scored more points.
  lost,

  /// Equal points.
  draw;

  /// Stable wire token.
  String get wireValue => switch (this) {
    DuelOutcome.won => 'won',
    DuelOutcome.lost => 'lost',
    DuelOutcome.draw => 'draw',
  };
}

/// A stored challenge with what a player needs to see about it: the
/// fixture, the challenger's name and how many seats are taken.
final class DuelChallengePreview {
  /// Creates the preview.
  const DuelChallengePreview({
    required this.challengeId,
    required this.code,
    required this.seasonId,
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.challengerUserId,
    required this.challengerName,
    required this.targetUserId,
    required this.capacity,
    required this.acceptedCount,
    required this.status,
    required this.createdAt,
  });

  /// The challenge identity.
  final DuelChallengeId challengeId;

  /// The share code.
  final DuelCode code;

  /// The season the challenge belongs to.
  final SeasonId seasonId;

  /// The fixture being predicted.
  final FixtureRef fixture;

  /// Home side name.
  final String homeTeam;

  /// Away side name.
  final String awayTeam;

  /// Kickoff instant (UTC).
  final DateTime kickoffAt;

  /// The account that created the challenge.
  final UserId challengerUserId;

  /// The challenger's display name.
  final String challengerName;

  /// The private target, or null for an open challenge.
  final UserId? targetUserId;

  /// Maximum accepted duels.
  final int capacity;

  /// Duels accepted so far.
  final int acceptedCount;

  /// The stored lifecycle state.
  final DuelChallengeStatus status;

  /// Creation instant (UTC).
  final DateTime createdAt;

  /// The state a player sees at [now]. A closed challenge keeps its stored
  /// state; an open one is expired from kickoff on (the instant the 0090
  /// accept function starts refusing) and full once every seat is taken.
  DuelChallengeState stateAt(DateTime now) {
    if (status == DuelChallengeStatus.cancelled) {
      return DuelChallengeState.cancelled;
    }
    if (status == DuelChallengeStatus.declined) {
      return DuelChallengeState.declined;
    }
    if (!now.isBefore(kickoffAt)) {
      return DuelChallengeState.expired;
    }
    if (acceptedCount >= capacity) {
      return DuelChallengeState.full;
    }
    return DuelChallengeState.open;
  }
}

/// A challenge as one caller sees it.
final class DuelChallengeView {
  /// Creates the view.
  const DuelChallengeView({
    required this.challenge,
    required this.state,
    required this.callerIsChallenger,
    required this.callerIsTarget,
  });

  /// The stored challenge.
  final DuelChallengePreview challenge;

  /// Its derived state at the time of the request.
  final DuelChallengeState state;

  /// Whether the caller created it.
  final bool callerIsChallenger;

  /// Whether the caller is its private target.
  final bool callerIsTarget;
}

/// One side's prediction in a duel.
final class DuelPick {
  /// Creates the pick.
  const DuelPick({
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
  });

  /// Predicted home goals.
  final int homeGoals;

  /// Predicted away goals.
  final int awayGoals;

  /// Whether the pick was the day's double.
  final bool isDouble;
}

/// One side's official fixture score (`scoring.fixture_scores`).
final class DuelScore {
  /// Creates the score.
  const DuelScore({required this.grade, required this.points});

  /// The stored grade token; `pending` means no final result yet.
  final String grade;

  /// The official fixture points, double included.
  final int points;

  /// Whether this score is final.
  bool get isFinal => grade != 'pending';
}

/// An accepted duel as stored, seen from one of its two players. Nothing
/// here is masked yet: `ListMyDuels` hides the opponent's pick before
/// kickoff.
final class DuelRecord {
  /// Creates the record.
  const DuelRecord({
    required this.duelId,
    required this.challengeId,
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.acceptedAt,
    required this.callerIsChallenger,
    required this.opponentUserId,
    required this.opponentName,
    required this.myPick,
    required this.opponentPick,
    required this.myScore,
    required this.opponentScore,
  });

  /// The duel identity.
  final DuelId duelId;

  /// The challenge it was accepted from.
  final DuelChallengeId challengeId;

  /// The fixture both players predicted.
  final FixtureRef fixture;

  /// Home side name.
  final String homeTeam;

  /// Away side name.
  final String awayTeam;

  /// Kickoff instant (UTC).
  final DateTime kickoffAt;

  /// When the duel was accepted (UTC).
  final DateTime acceptedAt;

  /// Whether the caller created the challenge.
  final bool callerIsChallenger;

  /// The other player.
  final UserId opponentUserId;

  /// The other player's display name.
  final String opponentName;

  /// The caller's prediction, read live from `prediction.fixture_predictions`.
  final DuelPick? myPick;

  /// The opponent's prediction, unmasked.
  final DuelPick? opponentPick;

  /// The caller's official fixture score, when one exists.
  final DuelScore? myScore;

  /// The opponent's official fixture score, when one exists.
  final DuelScore? opponentScore;

  /// This record with the opponent's prediction removed.
  DuelRecord withoutOpponentPick() => DuelRecord(
    duelId: duelId,
    challengeId: challengeId,
    fixture: fixture,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    kickoffAt: kickoffAt,
    acceptedAt: acceptedAt,
    callerIsChallenger: callerIsChallenger,
    opponentUserId: opponentUserId,
    opponentName: opponentName,
    myPick: myPick,
    opponentPick: null,
    myScore: myScore,
    opponentScore: opponentScore,
  );
}

/// A duel as the caller may see it: the opponent's pick only from kickoff
/// on, the points and the outcome only once both scores are final.
final class DuelView {
  /// Creates the view.
  const DuelView({
    required this.record,
    required this.state,
    required this.myPoints,
    required this.opponentPoints,
    required this.outcome,
  });

  /// The duel, with the opponent's prediction already removed before
  /// kickoff.
  final DuelRecord record;

  /// Where the duel stands.
  final DuelState state;

  /// The caller's points, null until settled.
  final int? myPoints;

  /// The opponent's points, null until settled.
  final int? opponentPoints;

  /// The result for the caller, null until settled.
  final DuelOutcome? outcome;
}

/// Everything `GET /me/duels` answers.
final class MyDuels {
  /// Creates the answer.
  const MyDuels({required this.challenges, required this.duels});

  /// Open challenges the caller created or was invited to privately.
  final List<DuelChallengeView> challenges;

  /// The caller's duels, newest kickoff first.
  final List<DuelView> duels;
}
