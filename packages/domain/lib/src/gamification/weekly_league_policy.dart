import 'package:domain/src/identity/user_id.dart';

/// The tier ladder of the weekly league (P2-2).
///
/// Stored in the database as the plain number `weekly_leagues.tier`
/// (migration 0061), named here for the same reason `GamificationEventType`
/// is the authority over `events.event_type`: how many tiers there are is
/// policy, and policy must not need a migration to change.
///
/// The Arabic labels live in the mobile l10n, never here: the domain names
/// the rung, the presentation names it in the reader's language.
enum WeeklyLeagueTier {
  /// The tier every player starts in. Nothing falls out of it.
  bronze(1),

  /// Second rung.
  silver(2),

  /// Third rung.
  gold(3),

  /// Fourth rung.
  platinum(4),

  /// The top rung. Nothing is promoted out of it.
  elite(5);

  const WeeklyLeagueTier(this.level);

  /// The value stored in `gamification.weekly_leagues.tier`.
  final int level;

  /// The tier stored as [level], or null if the number names no tier.
  ///
  /// Null rather than a throw: a row written by a future generation of the
  /// ladder is data this generation does not understand, not a crash.
  static WeeklyLeagueTier? ofLevel(int level) {
    for (final tier in values) {
      if (tier.level == level) {
        return tier;
      }
    }
    return null;
  }

  /// Whether promotion out of this tier is possible.
  bool get canPromote => this != elite;

  /// Whether relegation out of this tier is possible.
  bool get canRelegate => this != bronze;

  /// The tier above, or this one when already at the top.
  WeeklyLeagueTier get above => canPromote ? values[index + 1] : this;

  /// The tier below, or this one when already at the bottom.
  WeeklyLeagueTier get below => canRelegate ? values[index - 1] : this;
}

/// What a week did to a member's tier.
enum WeeklyLeagueOutcome {
  /// Moves up a tier next week.
  promoted('promoted'),

  /// Stays in the same tier next week.
  held('held'),

  /// Moves down a tier next week.
  relegated('relegated');

  const WeeklyLeagueOutcome(this.wireName);

  /// The value carried in the `weekly_league_finished` event payload.
  final String wireName;
}

/// One member's week, as the policy needs to see it.
///
/// Carries no name and no avatar: ranking is arithmetic, and presentation
/// data joined in here would make the policy untestable without a database.
final class WeeklyLeagueEntry {
  /// Creates an entry.
  const WeeklyLeagueEntry({
    required this.userId,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.joinedAt,
  });

  /// The platform user this week belongs to.
  final UserId userId;

  /// Points earned inside the week: scored fixture points plus streak
  /// bonuses, summed by the caller over the fixtures of the week. Never
  /// computed here -- Axiom 5, the policy ranks what scoring produced.
  final int points;

  /// Exact scorelines called right inside the week. First tie-break.
  final int exactCount;

  /// Fixtures of the week that have been decided for this member. Second
  /// tie-break: at equal points and equal exact calls, the member who
  /// reached them over fewer decided fixtures ranks higher.
  final int decidedCount;

  /// When the member took their seat in the group. Third tie-break.
  final DateTime joinedAt;
}

/// One member's place at the end of the week.
final class WeeklyLeaguePlacing {
  /// Creates a placing.
  const WeeklyLeaguePlacing({
    required this.entry,
    required this.rank,
    required this.outcome,
  });

  /// The member's week.
  final WeeklyLeagueEntry entry;

  /// 1-based position in the group. Every rank is distinct: the tie-break
  /// chain is total, so no two members can share a place.
  final int rank;

  /// Where the member goes next week.
  final WeeklyLeagueOutcome outcome;
}

/// The rules of the weekly league (P2-2, decided 2026-09-20).
///
/// Pure data and arithmetic. It reads no clock, no database and no fixture:
/// the caller hands it a Riyadh day or a finished group, and it answers.
///
/// **The week is Monday 00:00 through Sunday 23:59, Riyadh.** Not Saturday:
/// the heavy fixtures -- European on Saturday and Sunday, Saudi on Thursday
/// through Saturday -- then fall at the END of the week, so the group is
/// decided in its last hours. A Saturday start would settle the race on day
/// two and leave five dead days behind it.
///
/// **Placement is by position, and every position is distinct.** The chain
/// is points, then exact scorelines, then fewer decided fixtures, then the
/// earlier seat, then the user id. A published total order is what lets the
/// promotion line fall between two members without arbitration; a shared
/// "1224" rank would leave the line ambiguous exactly where it matters.
///
/// **Movement is proportional: `min(5, size / 4)` up and the same down.**
/// One formula, no special case for a thin group: twenty members move five,
/// eight members move two, four members move one. Nothing is promoted out of
/// [WeeklyLeagueTier.elite] and nothing is relegated out of
/// [WeeklyLeagueTier.bronze].
///
/// **A member who scored nothing is never promoted**, whatever their place.
/// In a group where few played, a zero could otherwise ride the formula
/// upward; the tier must mean a week that was played.
///
/// **No points are paid** for promotion, for a placing, or for winning a
/// group. The monthly board carries the real prize, and paying the weekly
/// winner into it would let the leader win twice and widen the gap the
/// weekly league exists to close. The reward is the tier and the badge.
final class WeeklyLeaguePolicy {
  const WeeklyLeaguePolicy._();

  /// Members one group accepts before a new group of the same tier and week
  /// is opened.
  static const int groupCapacity = 20;

  /// The most members one group may move in either direction.
  static const int maxMovement = 5;

  /// Members per moved place: a group of [movementDivisor] moves one.
  static const int movementDivisor = 4;

  /// The Monday that opens the Riyadh week containing [riyadhDay].
  ///
  /// [riyadhDay] is a Riyadh calendar day as a UTC midnight -- what
  /// `riyadhDayOf` produces. The result is the same shape, so it is stored
  /// straight into `weekly_leagues.week_start`.
  static DateTime weekStartOf(DateTime riyadhDay) {
    final day = DateTime.utc(riyadhDay.year, riyadhDay.month, riyadhDay.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// The Monday that opens the week AFTER the one containing [riyadhDay] --
  /// the exclusive end of that week.
  static DateTime weekEndOf(DateTime riyadhDay) =>
      weekStartOf(riyadhDay).add(const Duration(days: 7));

  /// Whether [riyadhDay] falls inside the week opened by [weekStart].
  static bool weekContains(DateTime weekStart, DateTime riyadhDay) {
    final start = weekStartOf(weekStart);
    final day = DateTime.utc(riyadhDay.year, riyadhDay.month, riyadhDay.day);
    return !day.isBefore(start) &&
        day.isBefore(start.add(const Duration(days: 7)));
  }

  /// How many members a group of [groupSize] moves in each direction.
  ///
  /// Zero for a group too small to move anyone, so a group of three plays
  /// for the placing alone.
  static int movementCount(int groupSize) {
    if (groupSize <= 0) {
      return 0;
    }
    final proportional = groupSize ~/ movementDivisor;
    return proportional < maxMovement ? proportional : maxMovement;
  }

  /// Orders [entries] by the published total order, best first.
  static List<WeeklyLeagueEntry> order(List<WeeklyLeagueEntry> entries) {
    final sorted = List<WeeklyLeagueEntry>.of(entries)
      ..sort((a, b) {
        final byPoints = b.points.compareTo(a.points);
        if (byPoints != 0) {
          return byPoints;
        }
        final byExact = b.exactCount.compareTo(a.exactCount);
        if (byExact != 0) {
          return byExact;
        }
        final byDecided = a.decidedCount.compareTo(b.decidedCount);
        if (byDecided != 0) {
          return byDecided;
        }
        final bySeat = a.joinedAt.compareTo(b.joinedAt);
        if (bySeat != 0) {
          return bySeat;
        }
        return a.userId.value.compareTo(b.userId.value);
      });
    return List<WeeklyLeagueEntry>.unmodifiable(sorted);
  }

  /// Judges a finished group: every member, best first, with their place and
  /// where they go next week.
  ///
  /// An empty group yields an empty list -- a tier nobody played in is not an
  /// error.
  static List<WeeklyLeaguePlacing> judge({
    required WeeklyLeagueTier tier,
    required List<WeeklyLeagueEntry> entries,
  }) {
    final ordered = order(entries);
    final movement = movementCount(ordered.length);
    final promotions = tier.canPromote ? movement : 0;
    final relegations = tier.canRelegate ? movement : 0;
    final relegationFrom = ordered.length - relegations;

    final placings = <WeeklyLeaguePlacing>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i];
      final outcome = switch (i) {
        // A member who scored nothing holds whatever their place: the tier
        // must mean a week that was played.
        _ when i < promotions && entry.points > 0 =>
          WeeklyLeagueOutcome.promoted,
        _ when i >= relegationFrom && relegations > 0 =>
          WeeklyLeagueOutcome.relegated,
        _ => WeeklyLeagueOutcome.held,
      };
      placings.add(
        WeeklyLeaguePlacing(entry: entry, rank: i + 1, outcome: outcome),
      );
    }
    return List<WeeklyLeaguePlacing>.unmodifiable(placings);
  }

  /// The tier [placing] plays in next week.
  static WeeklyLeagueTier nextTier(
    WeeklyLeagueTier tier,
    WeeklyLeagueOutcome outcome,
  ) => switch (outcome) {
    WeeklyLeagueOutcome.promoted => tier.above,
    WeeklyLeagueOutcome.relegated => tier.below,
    WeeklyLeagueOutcome.held => tier,
  };
}
