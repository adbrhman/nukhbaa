/// "Learn from your predictions" (plan P4-1..P4-3): accuracy, patterns and
/// last week's recap, counted from a player's scored predictions.
///
/// **Derived, never stored.** The plan proposed an insights table and a
/// recap table filled by a weekly job; here they are computed on every read
/// from `scoring.fixture_scores`, for the reason there is no streak table
/// (`StreakTally`): a stored copy is a second truth that can disagree with
/// the first, and a corrected result would leave it wrong.
///
/// Every day and week here is a Riyadh day, like the rest of the game.
library;

/// How one scored prediction ended.
enum PredictionGrade {
  /// The exact scoreline.
  exact,

  /// The right winner or draw, not the scoreline.
  correct,

  /// Wrong.
  incorrect,
}

/// One scored prediction of one player.
final class PredictionOutcome {
  /// Creates an outcome.
  const PredictionOutcome({
    required this.fixtureId,
    required this.kickoffAt,
    required this.homeTeam,
    required this.awayTeam,
    required this.grade,
    required this.points,
    required this.followed,
    this.leagueName,
  });

  /// The fixture predicted.
  final String fixtureId;

  /// When it kicked off (UTC).
  final DateTime kickoffAt;

  /// The home side, as the schedule names it.
  final String homeTeam;

  /// The away side, as the schedule names it.
  final String awayTeam;

  /// How the prediction ended.
  final PredictionGrade grade;

  /// Points it earned.
  final int points;

  /// Whether one of the two sides is a team the player follows (0065).
  final bool followed;

  /// The league's name, or null when the fixture has none on record.
  final String? leagueName;

  /// Right winner or draw, exact or not.
  bool get isCorrect => grade != PredictionGrade.incorrect;
}

/// Decided predictions and how many were right.
final class AccuracyTally {
  /// Creates a tally.
  const AccuracyTally({
    required this.decided,
    required this.correct,
    required this.exact,
  });

  /// Counts [outcomes].
  factory AccuracyTally.of(Iterable<PredictionOutcome> outcomes) {
    var decided = 0;
    var correct = 0;
    var exact = 0;
    for (final outcome in outcomes) {
      decided++;
      if (outcome.isCorrect) {
        correct++;
      }
      if (outcome.grade == PredictionGrade.exact) {
        exact++;
      }
    }
    return AccuracyTally(decided: decided, correct: correct, exact: exact);
  }

  /// Nothing decided.
  static const AccuracyTally empty = AccuracyTally(
    decided: 0,
    correct: 0,
    exact: 0,
  );

  /// Predictions whose fixture has a result.
  final int decided;

  /// Of those, the ones with the right winner or draw.
  final int correct;

  /// Of those, the exact scorelines.
  final int exact;

  /// Whole percent right, or null when nothing was decided: never a
  /// division by zero, and never a "0%" for a player who has not played.
  int? get percent => decided == 0 ? null : (correct * 100 / decided).round();
}

/// A player's accuracy in one league.
final class LeagueAccuracy {
  /// Creates a league line.
  const LeagueAccuracy({required this.name, required this.tally});

  /// The league's name.
  final String name;

  /// The player's accuracy in it.
  final AccuracyTally tally;
}

/// A player's accuracy in one Riyadh week.
final class WeekAccuracy {
  /// Creates a week line.
  const WeekAccuracy({required this.weekStart, required this.tally});

  /// The Monday opening the week, as a UTC midnight carrying its date.
  final DateTime weekStart;

  /// The player's accuracy in it.
  final AccuracyTally tally;
}

/// The recap of one finished week (plan P4-3).
final class WeekRecap {
  /// Creates a recap.
  const WeekRecap({
    required this.weekStart,
    required this.tally,
    required this.points,
    this.best,
  });

  /// The Monday opening the week, as a UTC midnight carrying its date.
  final DateTime weekStart;

  /// The week's accuracy.
  final AccuracyTally tally;

  /// Points earned by the week's predictions.
  final int points;

  /// The prediction that earned the most, earliest on a tie; null when
  /// none earned anything.
  final PredictionOutcome? best;
}

/// Everything "learn from your predictions" shows (plan P4-1..P4-3).
final class PredictionInsights {
  const PredictionInsights._({
    required this.month,
    required this.leagues,
    required this.weeks,
    required this.longestCorrectRun,
    this.bestLeague,
    this.worstLeague,
    this.followed,
    this.others,
    this.lastWeek,
  });

  /// The offset every day boundary here is read in: Riyadh, UTC+3.
  static const Duration riyadhOffset = Duration(hours: 3);

  /// How many weeks the weekly series covers, the current one included.
  static const int weekCount = 8;

  /// A league needs this many decided predictions before it can be named
  /// the best or the worst: two lucky calls are not a pattern.
  static const int minLeagueSample = 5;

  /// Followed and other teams each need this many before they are
  /// compared.
  static const int minBiasSample = 3;

  /// This Riyadh month's accuracy.
  final AccuracyTally month;

  /// Accuracy per league across the whole window, most played first.
  final List<LeagueAccuracy> leagues;

  /// The last [weekCount] weeks, oldest first, the current one last.
  final List<WeekAccuracy> weeks;

  /// The longest run of right predictions in the window, in kickoff order.
  final int longestCorrectRun;

  /// The league with the best accuracy, when two qualify and differ.
  final String? bestLeague;

  /// The league with the worst accuracy, when two qualify and differ.
  final String? worstLeague;

  /// Accuracy on fixtures of a followed team, when both samples suffice.
  final AccuracyTally? followed;

  /// Accuracy on every other fixture, alongside [followed].
  final AccuracyTally? others;

  /// Last week's recap, or null when last week had no decided prediction.
  final WeekRecap? lastWeek;

  /// The Riyadh day of [instant], as a UTC midnight carrying its date.
  static DateTime riyadhDayOf(DateTime instant) {
    final DateTime local = instant.toUtc().add(riyadhOffset);
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// The Monday opening the week of [day] (a Riyadh day).
  static DateTime mondayOf(DateTime day) =>
      day.subtract(Duration(days: day.weekday - DateTime.monday));

  /// The first Riyadh day the insights of [today] read from: the earlier
  /// of this month's first day and the oldest week of the series.
  static DateTime windowStart(DateTime today) {
    final DateTime monthStart = DateTime.utc(today.year, today.month);
    final DateTime oldestWeek = mondayOf(
      today,
    ).subtract(const Duration(days: 7 * (weekCount - 1)));
    return monthStart.isBefore(oldestWeek) ? monthStart : oldestWeek;
  }

  /// Computes the insights of [outcomes] as seen on [today] (a Riyadh day).
  static PredictionInsights compute({
    required List<PredictionOutcome> outcomes,
    required DateTime today,
  }) {
    final List<PredictionOutcome> ordered = List<PredictionOutcome>.of(outcomes)
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final DateTime monthStart = DateTime.utc(today.year, today.month);
    final DateTime monday = mondayOf(today);

    final AccuracyTally month = AccuracyTally.of(
      ordered.where((o) => !riyadhDayOf(o.kickoffAt).isBefore(monthStart)),
    );

    final Map<String, List<PredictionOutcome>> byLeague =
        <String, List<PredictionOutcome>>{};
    for (final outcome in ordered) {
      final String? name = outcome.leagueName;
      if (name != null && name.trim().isNotEmpty) {
        byLeague.putIfAbsent(name, () => <PredictionOutcome>[]).add(outcome);
      }
    }
    final List<LeagueAccuracy> leagues = <LeagueAccuracy>[
      for (final entry in byLeague.entries)
        LeagueAccuracy(name: entry.key, tally: AccuracyTally.of(entry.value)),
    ]..sort((a, b) => b.tally.decided.compareTo(a.tally.decided));
    final List<LeagueAccuracy> qualified = <LeagueAccuracy>[
      for (final league in leagues)
        if (league.tally.decided >= minLeagueSample) league,
    ]..sort((a, b) => b.tally.percent!.compareTo(a.tally.percent!));
    final bool ranked =
        qualified.length >= 2 &&
        qualified.first.tally.percent != qualified.last.tally.percent;

    final AccuracyTally followedTally = AccuracyTally.of(
      ordered.where((o) => o.followed),
    );
    final AccuracyTally othersTally = AccuracyTally.of(
      ordered.where((o) => !o.followed),
    );
    final bool compared =
        followedTally.decided >= minBiasSample &&
        othersTally.decided >= minBiasSample;

    var longest = 0;
    var run = 0;
    for (final outcome in ordered) {
      run = outcome.isCorrect ? run + 1 : 0;
      if (run > longest) {
        longest = run;
      }
    }

    final List<WeekAccuracy> weeks = <WeekAccuracy>[];
    for (var i = weekCount - 1; i >= 0; i--) {
      final DateTime start = monday.subtract(Duration(days: 7 * i));
      weeks.add(
        WeekAccuracy(
          weekStart: start,
          tally: AccuracyTally.of(_inWeek(ordered, start)),
        ),
      );
    }

    final DateTime lastMonday = monday.subtract(const Duration(days: 7));
    final List<PredictionOutcome> lastWeekOutcomes = _inWeek(
      ordered,
      lastMonday,
    );
    WeekRecap? lastWeek;
    if (lastWeekOutcomes.isNotEmpty) {
      PredictionOutcome? best;
      var points = 0;
      for (final outcome in lastWeekOutcomes) {
        points += outcome.points;
        if (outcome.points > 0 &&
            (best == null || outcome.points > best.points)) {
          best = outcome;
        }
      }
      lastWeek = WeekRecap(
        weekStart: lastMonday,
        tally: AccuracyTally.of(lastWeekOutcomes),
        points: points,
        best: best,
      );
    }

    return PredictionInsights._(
      month: month,
      leagues: List<LeagueAccuracy>.unmodifiable(leagues),
      weeks: List<WeekAccuracy>.unmodifiable(weeks),
      longestCorrectRun: longest,
      bestLeague: ranked ? qualified.first.name : null,
      worstLeague: ranked ? qualified.last.name : null,
      followed: compared ? followedTally : null,
      others: compared ? othersTally : null,
      lastWeek: lastWeek,
    );
  }

  static List<PredictionOutcome> _inWeek(
    List<PredictionOutcome> ordered,
    DateTime monday,
  ) {
    final DateTime next = monday.add(const Duration(days: 7));
    return <PredictionOutcome>[
      for (final outcome in ordered)
        if (!riyadhDayOf(outcome.kickoffAt).isBefore(monday) &&
            riyadhDayOf(outcome.kickoffAt).isBefore(next))
          outcome,
    ];
  }
}
