/// What a [GamificationEvent] records.
///
/// This enum — not a Postgres enum — is the authoritative vocabulary of
/// `gamification.events.event_type` (migration 0053 states why the column is
/// text: a Postgres enum value cannot be used in the transaction that added
/// it, SQLSTATE 55P04, so every phase of the plan would need a migration
/// split in two).
///
/// A value is added here only together with the code that emits it. An event
/// type nothing emits is a promise, not a record.
enum GamificationEventType {
  /// A participant submitted a prediction for a fixture for the first time.
  /// An amendment is not a new placement and emits nothing.
  predictionPlaced('prediction_placed'),

  /// A participant holds a prediction for EVERY fixture of one Riyadh match
  /// day. Emitted at the moment the last of them is submitted, never at the
  /// end of the day: fixtures are added during the day by the provider sync
  /// and by admins, so an end-of-day check would fail a day the participant
  /// had in fact finished. Because the stream is append-only, a day that
  /// completes stays complete even if a fixture appears afterwards.
  dailyChallengeCompleted('daily_challenge_completed'),

  /// A judged week of the weekly league ended for one member, carrying
  /// `{tier, rank, points, outcome}` in its payload (P2). It is the frozen
  /// standing of that week and the only record of which tier a player is
  /// promoted or relegated to, which is why no results table exists.
  ///
  /// Read by `WeeklyLeagueRepository.lastFinishOf` from P2-3; emitted by the
  /// week-closing job in P2-5. A reader landing first is not a promise: the
  /// value is already consulted the moment this ships.
  weeklyLeagueFinished('weekly_league_finished'),

  /// A player earned a badge of the catalog (P2-6). The payload carries the
  /// badge as `{code}`, and the dedupe key is the user and the code, so a
  /// badge is held once and cannot be granted twice or taken back. It carries
  /// no points: a badge is a record, not an award.
  ///
  /// Emitted by `EvaluateBadges`; read back by the badge reader, which
  /// treats the stored codes as the badges already held.
  badgeUnlocked('badge_unlocked');

  const GamificationEventType(this.wireName);

  /// The value stored in `gamification.events.event_type`.
  final String wireName;
}
