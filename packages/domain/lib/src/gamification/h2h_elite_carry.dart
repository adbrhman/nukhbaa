/// How a month of the elite draw carries into the next one (NK275, decided
/// by the owner on 2026-11-14).
///
/// * **The four elite groups.** The last [eliteRelegated] of each group by
///   its table go down to the first extra group (المجموعة 5). The rest stay
///   and, with the players who come up, are ranked by the month (the place
///   in the group, then prediction points, exact scorelines and league
///   points) and dealt again into four even groups by
///   `H2hLeaguePolicy.eliteDraw`.
/// * **Up to the elite.** The seats left are taken from the first two extra
///   groups (المجموعة 5 and 6) together, the most committed first
///   ([compareCommitment]); further groups only when those two run short.
/// * **Between the extra groups.** The last [ladderMoves] of each extra
///   group by its table go down one group, and the [ladderMoves] most
///   committed of the group below come up. The last group sends nobody
///   down.
/// * **Twenty a group.** The carried players are listed elite first, then
///   group by group, each group's list the most committed first; the draw
///   cuts the list twenty at a time, so a group that came out with one too
///   many sends its least committed to the group below.
/// * A member who predicted on too few days ([eligible]) is not carried
///   (outcome `out`); he may come back at the bottom as a new player.
/// * **NK277 (December 2026 on): a group that did not take part**
///   (`H2hEliteGroup.counted` false: it started with fewer than seven
///   rounds left, or never started) sends nobody up or down. Its carried
///   players come after every other group, its results kept: the more
///   committed first, a player with no round played after them in the
///   order he joined (`H2hEliteFinish.counted` false, outcome `held`).
///
/// Pure: no clock, no I/O.
library;

import 'package:domain/src/gamification/h2h_league_policy.dart';
import 'package:domain/src/identity/user_id.dart';

/// What a player did in his rounds of a month: the measure of commitment
/// that decides who comes up (owner, 2026-11-14).
final class H2hCommitment {
  /// Creates a measure.
  const H2hCommitment({
    required this.absentRounds,
    required this.predicted,
    required this.exact,
    required this.outcomes,
    required this.points,
  });

  /// No measure at all: the least committed there can be.
  static const H2hCommitment unknown = H2hCommitment(
    absentRounds: 1 << 30,
    predicted: 0,
    exact: 0,
    outcomes: 0,
    points: 0,
  );

  /// Rounds of the player's seats in which he predicted nothing. Fewer is
  /// better: the first criterion.
  final int absentRounds;

  /// Predictions he made on the fixtures of those rounds. Second.
  final int predicted;

  /// Exact scorelines among them. Third.
  final int exact;

  /// Right outcomes with the wrong score among them. Fourth.
  final int outcomes;

  /// Prediction points on them. Fifth.
  final int points;
}

/// Where one member of a judged elite month goes next.
final class H2hEliteFinish {
  /// Creates a finish.
  const H2hEliteFinish({
    required this.placing,
    required this.division,
    required this.groupNumber,
    required this.nextDivision,
    required this.nextOrder,
    required this.outcome,
    this.counted = true,
  });

  /// The member's place in his own group.
  final H2hPlacing placing;

  /// The division he played (`eliteDivision` or `extraDivision`).
  final H2hDivision division;

  /// The group he played, as players see it: 1 .. 4 elite, 5 and up extra.
  final int groupNumber;

  /// The division he plays next month, or null when he is not carried.
  final H2hDivision? nextDivision;

  /// His place in the next month's drawing order, 0 first, or null when he
  /// is not carried. The draw deals the list in this order.
  final int? nextOrder;

  /// Up, the same level, down, or out.
  final H2hLeagueOutcome outcome;

  /// NK277: false when his group took no part in the month's promotion
  /// and relegation (the event's reason `not_counted`).
  final bool counted;
}

/// One group of a judged elite month, as the closing job hands it in.
final class H2hEliteGroup {
  /// Creates a group.
  const H2hEliteGroup({
    required this.division,
    required this.groupIndex,
    required this.placings,
    this.counted = true,
  });

  /// `eliteDivision` or `extraDivision`.
  final H2hDivision division;

  /// The group's index in its division (`h2h_leagues.group_index`).
  final int groupIndex;

  /// The group's table, best first.
  final List<H2hPlacing> placings;

  /// NK277: whether the group takes part in the month's promotion and
  /// relegation (`H2hLeaguePolicy.countsForMovement`). An elite group
  /// always does.
  final bool counted;
}

/// The carry of an elite month (NK275).
abstract final class H2hEliteCarry {
  /// Players of each elite group who go down by the table.
  static const int eliteRelegated = 3;

  /// Players who go down, and who come up, between two extra groups.
  static const int ladderMoves = 5;

  /// How many extra groups (from the first) the elite's seats are filled
  /// from before any further group is looked at.
  static const int eliteFeederGroups = 2;

  /// The more committed of two players first: fewer absent rounds, more
  /// predictions, more exact scorelines, more right outcomes, more points,
  /// then the user id so the order is total.
  static int compareCommitment(
    UserId a,
    UserId b,
    Map<UserId, H2hCommitment> commitment,
  ) {
    final ca = commitment[a] ?? H2hCommitment.unknown;
    final cb = commitment[b] ?? H2hCommitment.unknown;
    final byAbsent = ca.absentRounds.compareTo(cb.absentRounds);
    if (byAbsent != 0) return byAbsent;
    final byPredicted = cb.predicted.compareTo(ca.predicted);
    if (byPredicted != 0) return byPredicted;
    final byExact = cb.exact.compareTo(ca.exact);
    if (byExact != 0) return byExact;
    final byOutcomes = cb.outcomes.compareTo(ca.outcomes);
    if (byOutcomes != 0) return byOutcomes;
    final byPoints = cb.points.compareTo(ca.points);
    if (byPoints != 0) return byPoints;
    return a.value.compareTo(b.value);
  }

  /// The finish of every member of [groups] (the elite month's groups,
  /// elite and extra), and so the next month's drawing order.
  static List<H2hEliteFinish> next({
    required List<H2hEliteGroup> groups,
    required Set<UserId> eligible,
    required Map<UserId, H2hCommitment> commitment,
  }) {
    int byCommitment(UserId a, UserId b) => compareCommitment(a, b, commitment);

    final elite = [
      for (final g in groups)
        if (g.division == H2hLeaguePolicy.eliteDivision) g,
    ]..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    final extra = [
      for (final g in groups)
        if (g.division != H2hLeaguePolicy.eliteDivision && g.counted) g,
    ]..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
    // NK277: the groups that took no part, in their order.
    final aside = [
      for (final g in groups)
        if (g.division != H2hLeaguePolicy.eliteDivision && !g.counted) g,
    ]..sort((a, b) => a.groupIndex.compareTo(b.groupIndex));

    // Every member once, with his group and placing.
    final placingOf = <UserId, H2hPlacing>{};
    final levelOf = <UserId, int>{}; // 0 elite, 1 + i the extra group i
    final groupNumberOf = <UserId, int>{};
    final divisionOf = <UserId, H2hDivision>{};
    for (final g in elite) {
      for (final p in g.placings) {
        placingOf[p.standing.userId] = p;
        levelOf[p.standing.userId] = 0;
        groupNumberOf[p.standing.userId] = g.groupIndex + 1;
        divisionOf[p.standing.userId] = g.division;
      }
    }
    for (var i = 0; i < extra.length; i++) {
      for (final p in extra[i].placings) {
        placingOf[p.standing.userId] = p;
        levelOf[p.standing.userId] = i + 1;
        groupNumberOf[p.standing.userId] =
            H2hLeaguePolicy.eliteGroups + extra[i].groupIndex + 1;
        divisionOf[p.standing.userId] = extra[i].division;
      }
    }
    bool carried(UserId u) => eligible.contains(u);

    // 1. The elite: the last three of each group go down.
    final eliteStay = <H2hPlacing>[];
    final eliteDown = <UserId>[];
    for (final g in elite) {
      final table = [...g.placings]..sort((a, b) => a.rank.compareTo(b.rank));
      final cut = table.length > eliteRelegated
          ? table.length - eliteRelegated
          : 0;
      for (var k = 0; k < table.length; k++) {
        final u = table[k].standing.userId;
        if (!carried(u)) continue;
        if (k < cut) {
          eliteStay.add(table[k]);
        } else {
          eliteDown.add(u);
        }
      }
    }

    // The extra groups' carried members, each group by its table.
    final extraTables = <List<UserId>>[
      for (final g in extra)
        [
          for (final p in [
            ...g.placings,
          ]..sort((a, b) => a.rank.compareTo(b.rank)))
            if (carried(p.standing.userId)) p.standing.userId,
        ],
    ];

    // 2. The elite's free seats, from groups 5 and 6 first.
    final carriedTotal =
        eliteStay.length +
        eliteDown.length +
        extraTables.fold<int>(0, (sum, t) => sum + t.length);
    final eliteTarget = carriedTotal < H2hLeaguePolicy.eliteSeats
        ? carriedTotal
        : H2hLeaguePolicy.eliteSeats;
    var need = eliteTarget - eliteStay.length;
    final toElite = <UserId>[];
    final feeders = <UserId>[
      for (var i = 0; i < extraTables.length && i < eliteFeederGroups; i++)
        ...extraTables[i],
    ]..sort(byCommitment);
    for (final u in feeders) {
      if (need <= 0) break;
      toElite.add(u);
      need--;
    }
    for (var i = eliteFeederGroups; i < extraTables.length && need > 0; i++) {
      final rest = [...extraTables[i]]..sort(byCommitment);
      for (final u in rest) {
        if (need <= 0) break;
        toElite.add(u);
        need--;
      }
    }
    // Too few below to replace them all: the best of those going down stay.
    eliteDown.sort((a, b) => _compareMonth(placingOf[a]!, placingOf[b]!));
    final eliteKeptBack = <UserId>[];
    while (need > 0 && eliteDown.isNotEmpty) {
      eliteKeptBack.add(eliteDown.removeAt(0));
      need--;
    }
    final promoted = toElite.toSet();

    // 3. The extra groups' ladder, on the players left in each group.
    final left = <List<UserId>>[
      for (final t in extraTables)
        [
          for (final u in t)
            if (!promoted.contains(u)) u,
        ],
    ];
    final up = <List<UserId>>[]; // up[i]: from group i to group i - 1
    for (var i = 0; i < left.length; i++) {
      if (i == 0) {
        up.add(const <UserId>[]);
        continue;
      }
      final ranked = [...left[i]]..sort(byCommitment);
      up.add(ranked.take(ladderMoves).toList());
    }
    final down = <List<UserId>>[]; // down[i]: from group i to group i + 1
    for (var i = 0; i < left.length; i++) {
      if (i == left.length - 1) {
        down.add(const <UserId>[]);
        continue;
      }
      final goingUp = up[i].toSet();
      final staying = [
        for (final u in left[i])
          if (!goingUp.contains(u)) u,
      ];
      final from = staying.length > ladderMoves
          ? staying.length - ladderMoves
          : 0;
      down.add(staying.sublist(from));
    }
    final tiers = <List<UserId>>[];
    for (var i = 0; i < left.length; i++) {
      final moving = {...up[i], ...down[i]};
      tiers.add(
        [
          if (i == 0) ...eliteDown,
          if (i > 0) ...down[i - 1],
          for (final u in left[i])
            if (!moving.contains(u)) u,
          if (i + 1 < left.length) ...up[i + 1],
        ]..sort(byCommitment),
      );
    }
    // An elite month with no extra group: whoever goes down opens one.
    if (left.isEmpty && eliteDown.isNotEmpty) {
      tiers.add([...eliteDown]..sort(byCommitment));
    }

    // NK277: the players of the groups that took no part, after every
    // tier: each group in its order, the more committed first, then those
    // with no round played in the order they joined.
    final asideOrder = <UserId>[];
    final asidePlacing = <UserId, H2hPlacing>{};
    final asideGroup = <UserId, H2hEliteGroup>{};
    for (final g in aside) {
      final members = <H2hPlacing>[
        for (final p in g.placings)
          if (!placingOf.containsKey(p.standing.userId)) p,
      ];
      for (final p in members) {
        asidePlacing[p.standing.userId] = p;
        asideGroup[p.standing.userId] = g;
      }
      final carriedHere =
          [
            for (final p in members)
              if (carried(p.standing.userId)) p,
          ]..sort((a, b) {
            final ka = commitment.containsKey(a.standing.userId);
            final kb = commitment.containsKey(b.standing.userId);
            if (ka && kb) {
              return byCommitment(a.standing.userId, b.standing.userId);
            }
            if (ka != kb) {
              return ka ? -1 : 1;
            }
            return a.standing.slot.compareTo(b.standing.slot);
          });
      asideOrder.addAll([for (final p in carriedHere) p.standing.userId]);
    }

    // 4. The order: the elite ranked by the month, then the tiers.
    final eliteNext = <UserId>[
      for (final p in [
        ...eliteStay,
        for (final u in eliteKeptBack) placingOf[u]!,
      ]..sort(_compareMonth))
        p.standing.userId,
      ...toElite,
    ];
    final orderOf = <UserId, int>{};
    final nextLevel = <UserId, int>{};
    var position = 0;
    for (final u in eliteNext) {
      orderOf[u] = position++;
      nextLevel[u] = 0;
    }
    for (var i = 0; i < tiers.length; i++) {
      for (final u in tiers[i]) {
        orderOf[u] = position++;
        nextLevel[u] = i + 1;
      }
    }
    for (final u in asideOrder) {
      orderOf[u] = position++;
    }

    return <H2hEliteFinish>[
      for (final entry in asidePlacing.entries)
        H2hEliteFinish(
          placing: entry.value,
          division: asideGroup[entry.key]!.division,
          groupNumber: H2hLeaguePolicy.groupNumberOf(
            division: asideGroup[entry.key]!.division,
            groupIndex: asideGroup[entry.key]!.groupIndex,
          ),
          nextDivision: orderOf[entry.key] == null
              ? null
              : H2hLeaguePolicy.extraDivision,
          nextOrder: orderOf[entry.key],
          outcome: orderOf[entry.key] == null
              ? H2hLeagueOutcome.out
              : H2hLeagueOutcome.held,
          counted: false,
        ),
      for (final entry in placingOf.entries)
        _finish(
          entry.value,
          divisionOf[entry.key]!,
          groupNumberOf[entry.key]!,
          levelOf[entry.key]!,
          nextLevel[entry.key],
          orderOf[entry.key],
        ),
    ];
  }

  static H2hEliteFinish _finish(
    H2hPlacing placing,
    H2hDivision division,
    int groupNumber,
    int level,
    int? next,
    int? order,
  ) {
    final H2hLeagueOutcome outcome;
    if (next == null) {
      outcome = H2hLeagueOutcome.out;
    } else if (next < level) {
      outcome = H2hLeagueOutcome.promoted;
    } else if (next > level) {
      outcome = H2hLeagueOutcome.relegated;
    } else {
      outcome = H2hLeagueOutcome.held;
    }
    return H2hEliteFinish(
      placing: placing,
      division: division,
      groupNumber: groupNumber,
      nextDivision: next == null
          ? null
          : (next == 0
                ? H2hLeaguePolicy.eliteDivision
                : H2hLeaguePolicy.extraDivision),
      nextOrder: order,
      outcome: outcome,
    );
  }

  /// The elite ranked by the month: the place in the group, then prediction
  /// points, exact scorelines, league points, then the id.
  static int _compareMonth(H2hPlacing a, H2hPlacing b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final sa = a.standing;
    final sb = b.standing;
    final byPoints = sb.pointsFor.compareTo(sa.pointsFor);
    if (byPoints != 0) return byPoints;
    final byExact = sb.exactCount.compareTo(sa.exactCount);
    if (byExact != 0) return byExact;
    final byLeague = sb.leaguePoints.compareTo(sa.leaguePoints);
    if (byLeague != 0) return byLeague;
    return sa.userId.value.compareTo(sb.userId.value);
  }
}
