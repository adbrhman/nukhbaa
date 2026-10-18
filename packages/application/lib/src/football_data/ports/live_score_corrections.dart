/// An admin's correction of a running score that the provider has wrong --
/// a goal ruled out by VAR that the feed still counts, for one (Paris FC -
/// Rennes, 2026-10-18: the feed kept 2-2 long after the 51st-minute goal was
/// ruled out).
///
/// The correction remembers the provider's figure it was made against
/// ([baseHomeGoals]-[baseAwayGoals]), so a goal the provider reports after it
/// still shows, and a fix the provider makes itself takes over.
final class LiveScoreCorrection {
  /// Creates the correction.
  const LiveScoreCorrection({
    required this.homeGoals,
    required this.awayGoals,
    required this.baseHomeGoals,
    required this.baseAwayGoals,
    required this.setAt,
  });

  /// Home goals as the admin says they stand.
  final int homeGoals;

  /// Away goals as the admin says they stand.
  final int awayGoals;

  /// Home goals the provider reported when the correction was made.
  final int baseHomeGoals;

  /// Away goals the provider reported when the correction was made.
  final int baseAwayGoals;

  /// When the admin made it, UTC.
  final DateTime setAt;

  /// The score that counts when the provider reports [home]-[away].
  ///
  /// * The provider still reports the figure the correction was made
  ///   against, or already reports the corrected one: the corrected score,
  ///   [settled].
  /// * The provider went back on a goal by itself (one side below the
  ///   figure the correction was made against): the provider's figure, not
  ///   [settled], since the two corrections may not be the same goal.
  /// * The provider reported goals after the correction: those goals on top
  ///   of the corrected score, not [settled], since it cannot be told from
  ///   here whether the provider also fixed what the admin fixed.
  ///
  /// A score that is not [settled] is shown, but the result sync does not
  /// record it before an admin confirms it or the match is late.
  ({int homeGoals, int awayGoals, bool settled}) applyTo(int home, int away) {
    if ((home == baseHomeGoals && away == baseAwayGoals) ||
        (home == homeGoals && away == awayGoals)) {
      return (homeGoals: homeGoals, awayGoals: awayGoals, settled: true);
    }
    if (home < baseHomeGoals || away < baseAwayGoals) {
      return (homeGoals: home, awayGoals: away, settled: false);
    }
    final shiftedHome = home + homeGoals - baseHomeGoals;
    final shiftedAway = away + awayGoals - baseAwayGoals;
    return (
      homeGoals: shiftedHome < 0 ? 0 : shiftedHome,
      awayGoals: shiftedAway < 0 ? 0 : shiftedAway,
      settled: false,
    );
  }
}

/// Where the admins' corrections of running scores are kept, by app fixture
/// id. Read by the live board (what players see and are graded on while the
/// match is in play) and by the result sync (what is recorded at full time).
abstract interface class LiveScoreCorrections {
  /// Stores [correction] for [fixtureId], replacing any earlier one.
  void set(String fixtureId, LiveScoreCorrection correction);

  /// Forgets the correction of [fixtureId], if any.
  void clear(String fixtureId);

  /// The correction of [fixtureId]; null when there is none.
  LiveScoreCorrection? of(String fixtureId);
}
