/// How long a user's run of completed match days is (P1-3).
///
/// Derived, never stored: the completion events in `gamification.events` are
/// the record, and this is what counting them yields. There is no streak
/// table and no cache, for the same reason `user_points_summary` was
/// dropped — a stored copy is a second truth that can disagree with the
/// first.
///
/// **Match days, not calendar days.** The unit is a day that HAD fixtures.
/// A day with none is not a day the user could have played, so it is absent
/// from the input entirely: an international break neither completes nor
/// breaks anything.
///
/// **No freeze and no grace** (decided 2026-09-19): one missed match day ends
/// the run. Should that prove too harsh in use, a freeze arrives as a third
/// event type, not as mutable state bolted onto a stored streak.
final class StreakTally {
  /// Creates a tally.
  const StreakTally({required this.current, required this.longest});

  /// Nobody has completed a day.
  static const StreakTally none = StreakTally(current: 0, longest: 0);

  /// How many match days in a row are complete, counting back from the most
  /// recent one.
  final int current;

  /// The longest such run inside the window that was counted.
  ///
  /// Bounded by that window: a run older than it is not visible here. The
  /// window is the caller's choice, and `GetMyStreak` sizes it well past a
  /// sporting season.
  final int longest;

  /// Counts [completions] — one entry per match day, NEWEST FIRST.
  ///
  /// Set [newestIsPendingToday] when the newest entry is today's match day
  /// and today is not finished. Today is then skipped rather than counted as
  /// a break: a day still in progress has not been missed. This is not a
  /// grace period — any EARLIER incomplete day ends the run at once.
  static StreakTally fromMatchDays(
    List<bool> completions, {
    bool newestIsPendingToday = false,
  }) {
    final start =
        newestIsPendingToday && completions.isNotEmpty && !completions.first
        ? 1
        : 0;

    var current = 0;
    for (var i = start; i < completions.length; i++) {
      if (!completions[i]) {
        break;
      }
      current++;
    }

    var longest = 0;
    var run = 0;
    for (final completed in completions) {
      if (completed) {
        run++;
        if (run > longest) {
          longest = run;
        }
      } else {
        run = 0;
      }
    }

    return StreakTally(
      current: current,
      longest: current > longest ? current : longest,
    );
  }
}
