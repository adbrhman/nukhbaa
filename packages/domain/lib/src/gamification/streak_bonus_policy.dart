/// One rung of the streak-bonus ladder (P1-4): a run of [threshold] match
/// days in a row earns [points], once.
final class StreakBonusRung {
  /// Creates a rung.
  const StreakBonusRung({required this.threshold, required this.points});

  /// How many match days in a row the run must have reached.
  final int threshold;

  /// The points the rung pays. Never negative: a bonus only adds.
  final int points;

  /// The ledger `source_ref` of this rung's entry: `streak:<threshold>`.
  ///
  /// The partial unique index on `(participant_id, source_ref)` for
  /// `streak_bonus` entries (migration 0057) is what lets a rung be paid at
  /// most once per participant, so this string is a storage contract and
  /// must not change once a bonus has been paid under it.
  String get sourceRef => 'streak:$threshold';
}

/// Which streak bonuses a run has earned (P1-4, decided 2026-09-19).
///
/// The ladder is 7 match days = 5 points, 14 = 10, 30 = 20. It is pure data
/// and arithmetic: whether a rung was already paid is the ledger's fact, not
/// this policy's, and reading the run is `StreakTally`'s job.
///
/// Eligibility is by the CURRENT run, never the longest: `longest` is shown
/// to the user but earns nothing. A rung is earned by `current >= threshold`
/// rather than `==`, so a bonus whose payment was missed once (a Tier-3
/// write) is still paid the next time the run is evaluated, as long as the
/// run survives.
final class StreakBonusPolicy {
  const StreakBonusPolicy._();

  /// The ladder, lowest threshold first.
  static const List<StreakBonusRung> rungs = <StreakBonusRung>[
    StreakBonusRung(threshold: 7, points: 5),
    StreakBonusRung(threshold: 14, points: 10),
    StreakBonusRung(threshold: 30, points: 20),
  ];

  /// Every rung a run of [currentStreak] match days has reached, lowest
  /// threshold first. Empty for a run shorter than the first rung.
  static List<StreakBonusRung> reachedBy(int currentStreak) =>
      <StreakBonusRung>[
        for (final rung in rungs)
          if (currentStreak >= rung.threshold) rung,
      ];
}
