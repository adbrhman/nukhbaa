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
  dailyChallengeCompleted('daily_challenge_completed');

  const GamificationEventType(this.wireName);

  /// The value stored in `gamification.events.event_type`.
  final String wireName;
}
