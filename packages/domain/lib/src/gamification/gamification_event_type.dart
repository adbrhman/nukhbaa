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
  predictionPlaced('prediction_placed');

  const GamificationEventType(this.wireName);

  /// The value stored in `gamification.events.event_type`.
  final String wireName;
}
