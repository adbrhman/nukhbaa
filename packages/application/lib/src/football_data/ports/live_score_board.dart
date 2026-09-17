/// A fixture's running score as last reported by a provider, kept for
/// display only: it never scores anything, and it is replaced by the recorded
/// result once an admin or the result sync enters one.
final class LiveScore {
  /// Creates the score.
  const LiveScore({
    required this.homeGoals,
    required this.awayGoals,
    required this.finished,
    required this.updatedAt,
    this.minute,
  });

  /// Home goals so far.
  final int homeGoals;

  /// Away goals so far.
  final int awayGoals;

  /// The match minute, when the provider reports one.
  final int? minute;

  /// The provider says the match is over (its result may not be recorded
  /// yet).
  final bool finished;

  /// When this score was read, UTC.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is LiveScore &&
      other.homeGoals == homeGoals &&
      other.awayGoals == awayGoals &&
      other.minute == minute &&
      other.finished == finished &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(homeGoals, awayGoals, minute, finished, updatedAt);
}

/// Where running scores live between a provider poll and the fixtures feed.
/// Short-lived by nature: an implementation forgets a score it has not heard
/// about for a while, so a stalled poll never leaves a stale score on screen.
abstract interface class LiveScoreBoard {
  /// Stores [scores], keyed by app fixture id.
  void put(Map<String, LiveScore> scores);

  /// Forgets the scores of [fixtureIds].
  void remove(Iterable<String> fixtureIds);

  /// The current scores of those [fixtureIds] that have one.
  Map<String, LiveScore> read(Iterable<String> fixtureIds);
}
