import 'package:shared/shared.dart';

/// Port: the store of settled match days (P1-5).
///
/// A "day" is a Riyadh calendar day, carried as a UTC midnight (the shape
/// `riyadhDayOf` returns). A settled day is frozen: the number of fixtures it
/// had when it was settled never changes afterwards, and a day with no
/// fixture is settled too, so the newest settled day is the watermark
/// "settled through here".
///
/// Implementations are total (Application ADR §2): they never throw, they
/// return a typed [Result].
abstract interface class MatchDaySettlementStore {
  /// The newest settled day, or `null` when nothing has been settled yet.
  Future<Result<DateTime?>> lastSettledDay();

  /// The Riyadh day of the earliest scheduled fixture, or `null` when no
  /// fixture is scheduled at all.
  Future<Result<DateTime?>> firstFixtureDay();

  /// Settles every day from [from] through [through], both inclusive, each
  /// with the number of fixtures that kick off in it right now.
  ///
  /// Idempotent: a day that is already settled is left exactly as it was.
  /// Returns how many days this call newly settled.
  Future<Result<int>> settle({
    required DateTime from,
    required DateTime through,
  });
}
