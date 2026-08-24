/// The pure "at most one double per participant per UTC calendar day" rule
/// (docs/project-context.md, Axiom 4 Amendment). Because each fixture is now
/// an independent prediction submitted at its own time (never a round's
/// atomic batch), this invariant cannot live inside a single `Prediction`
/// aggregate anymore — it is checked against a same-day count the caller
/// (application layer, via a repository query grouping by the UTC calendar
/// day of the fixtures' kickoff) supplies.
///
/// Pure and total: no query, no clock — just the counting rule.
final class DailyDoublePolicy {
  const DailyDoublePolicy._();

  /// The maximum number of fixtures a participant may mark as their double
  /// on the same UTC calendar day.
  static const int maxDoublesPerDay = 1;

  /// Whether marking one more fixture as the double is allowed, given
  /// [existingDoublesOnDay] already-recorded doubles for the same
  /// participant on the same UTC calendar day. When this call is an
  /// amendment of a prediction that is itself already one of those doubles,
  /// the caller's query must exclude it first.
  static bool allowsAnotherDouble(int existingDoublesOnDay) {
    assert(existingDoublesOnDay >= 0, 'a count cannot be negative');
    return existingDoublesOnDay < maxDoublesPerDay;
  }
}
