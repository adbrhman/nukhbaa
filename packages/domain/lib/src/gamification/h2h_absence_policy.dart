import 'package:domain/src/gamification/h2h_league_id.dart';
import 'package:domain/src/gamification/h2h_round_id.dart';
import 'package:domain/src/identity/user_id.dart';

/// Why a seat swap was made (migration 0189).
enum H2hSeatMoveKind {
  /// Three consecutive counted rounds without a prediction.
  absence('absence'),

  /// An admin relegated the player by hand (cheating, a breach), with a
  /// reason.
  admin('admin');

  const H2hSeatMoveKind(this.wireName);

  /// The value stored in `h2h_seat_moves.kind`.
  final String wireName;

  /// The kind stored as [raw], or null when it names none.
  static H2hSeatMoveKind? ofWire(String? raw) {
    for (final kind in values) {
      if (kind.wireName == raw) {
        return kind;
      }
    }
    return null;
  }
}

/// One round of the absence count: approved, locked, past its last
/// kickoff, with a fixture left, and not excused by an admin.
final class H2hCountedRound {
  /// Creates a counted round.
  const H2hCountedRound({
    required this.roundId,
    required this.monthStart,
    required this.number,
    required this.day,
    required this.present,
  });

  /// The round.
  final H2hRoundId roundId;

  /// The first day of its month, as a UTC midnight.
  final DateTime monthStart;

  /// Its number in the month.
  final int number;

  /// Its Riyadh day, as a UTC midnight.
  final DateTime day;

  /// The players who predicted at least one of its fixtures.
  final Set<UserId> present;
}

/// What a possible substitute is chosen on, over the window
/// ([H2hAbsencePolicy.windowDays] days ending on the last counted round).
final class H2hCandidateFacts {
  /// Creates the facts.
  const H2hCandidateFacts({
    required this.userId,
    required this.missed,
    required this.points,
    required this.exact,
    required this.activeDays,
  });

  /// The player.
  final UserId userId;

  /// Matches of the window he did not predict: fewer is more committed.
  final int missed;

  /// Points of the window, the double included.
  final int points;

  /// Exact scorelines of the window.
  final int exact;

  /// Riyadh days of the window with a prediction.
  final int activeDays;
}

/// A seat of the month as the absence job sees it: who holds it now.
final class H2hHeldSeat {
  /// Creates a held seat.
  const H2hHeldSeat({
    required this.userId,
    required this.leagueId,
    required this.groupIndex,
    required this.slot,
  });

  /// The holder.
  final UserId userId;

  /// The group.
  final H2hLeagueId leagueId;

  /// 0-based position of the group in its division.
  final int groupIndex;

  /// The seat's slot.
  final int slot;
}

/// A swap the absence job (or an admin) decided: [out] leaves [eliteSeat]
/// for [substitute]'s [extraSeat], from the next round.
final class H2hPlannedMove {
  /// Creates a planned move.
  const H2hPlannedMove({
    required this.out,
    required this.eliteSeat,
    required this.substitute,
    required this.extraSeat,
    required this.facts,
    required this.absentRounds,
  });

  /// The player who leaves the elite seat.
  final UserId out;

  /// The elite seat he leaves.
  final H2hHeldSeat eliteSeat;

  /// The player who takes it.
  final UserId substitute;

  /// The extra seat the substitute leaves to [out].
  final H2hHeldSeat extraSeat;

  /// What the substitute was chosen on.
  final H2hCandidateFacts facts;

  /// The rounds [out] missed in a row (empty for an admin's move).
  final List<H2hCountedRound> absentRounds;
}

/// An elite player relegated with nobody to take his seat: no extra player
/// met the conditions. The swap waits for the next round.
final class H2hUnfilledRelegation {
  /// Creates an unfilled relegation.
  const H2hUnfilledRelegation({required this.out, required this.eliteSeat});

  /// The player who should have left.
  final UserId out;

  /// His seat.
  final H2hHeldSeat eliteSeat;
}

/// The rules of relegation for absence (decided by the owner on
/// 2026-10-31, script 183). Pure: no clock, no database.
///
/// **The count.** A counted round ([H2hCountedRound]) is an approved round
/// of a month of the elite draw that has locked, whose last kickoff has
/// passed, that still holds a fixture and that no admin excused. A player
/// is absent from it when he predicted none of its fixtures. A day without
/// a round is not a round: it neither counts nor breaks the run. The run
/// goes on across months.
///
/// **The warning.** An elite player whose run reaches [warningStreak] is
/// told once; at [relegationStreak] he leaves his seat before the next
/// round, which must be round [lastEffectiveRound] at the latest.
///
/// **The substitute.** A holder of an extra seat (division 2) who was not
/// relegated this month, predicted on at least [minActiveDays] days of the
/// last [windowDays] days, and played each of the last [presentRounds]
/// counted rounds; the fewest matches missed first, then points, then exact
/// scorelines, then the id.
final class H2hAbsencePolicy {
  const H2hAbsencePolicy._();

  /// Consecutive counted absences that relegate an elite player.
  static const int relegationStreak = 3;

  /// Consecutive counted absences that warn him.
  static const int warningStreak = 2;

  /// The last round a swap may take effect from: the league's last round.
  static const int lastEffectiveRound = 19;

  /// Days the substitute's facts are read over.
  static const int windowDays = 30;

  /// Days of predictions a substitute needs in the window.
  static const int minActiveDays = 5;

  /// Counted rounds a substitute must have played, the latest ones.
  static const int presentRounds = 3;

  /// How long before the next round's first kickoff the swap is made, so an
  /// admin has every hour until then to excuse a round.
  static const Duration relegationLead = Duration(hours: 1);

  /// The trailing run of absences of [user] in [counted] (oldest first),
  /// oldest first: empty when he played the latest counted round.
  static List<H2hCountedRound> absenceRun(
    UserId user,
    List<H2hCountedRound> counted,
  ) {
    final run = <H2hCountedRound>[];
    for (var i = counted.length - 1; i >= 0; i--) {
      if (counted[i].present.contains(user)) {
        break;
      }
      run.insert(0, counted[i]);
    }
    return List<H2hCountedRound>.unmodifiable(run);
  }

  /// Whether [user] played each of the last [presentRounds] counted rounds
  /// (each of them, when fewer have been played).
  static bool playedLatest(UserId user, List<H2hCountedRound> counted) {
    final from = counted.length > presentRounds
        ? counted.length - presentRounds
        : 0;
    for (var i = from; i < counted.length; i++) {
      if (!counted[i].present.contains(user)) {
        return false;
      }
    }
    return true;
  }

  /// [facts] of the eligible substitutes, best first. [excluded] are the
  /// players who may not come up (relegated this month, or already chosen).
  static List<H2hCandidateFacts> rankCandidates({
    required List<H2hCandidateFacts> facts,
    required List<H2hCountedRound> counted,
    required Set<UserId> excluded,
  }) {
    final eligible = <H2hCandidateFacts>[
      for (final f in facts)
        if (!excluded.contains(f.userId) &&
            f.activeDays >= minActiveDays &&
            playedLatest(f.userId, counted))
          f,
    ]..sort(compareCandidates);
    return List<H2hCandidateFacts>.unmodifiable(eligible);
  }

  /// The order of substitutes: fewest missed, most points, most exact
  /// scorelines, then the user id.
  static int compareCandidates(H2hCandidateFacts a, H2hCandidateFacts b) {
    final byMissed = a.missed.compareTo(b.missed);
    if (byMissed != 0) {
      return byMissed;
    }
    final byPoints = b.points.compareTo(a.points);
    if (byPoints != 0) {
      return byPoints;
    }
    final byExact = b.exact.compareTo(a.exact);
    if (byExact != 0) {
      return byExact;
    }
    return a.userId.value.compareTo(b.userId.value);
  }

  /// The swaps to make before a round: every elite holder whose run of
  /// absences in [counted] reached [relegationStreak], in the order of the
  /// groups and seats, each with the best substitute left.
  ///
  /// [elite] and [extra] are the seats held now. [alreadyOut] are this
  /// month's relegated players: they are not relegated twice and never come
  /// back. [alreadyIn] were promoted this month already. [wouldRepeat] says
  /// whether a relegated player taking an extra seat would meet an opponent
  /// he already met this month; such a substitute is passed over.
  static ({List<H2hPlannedMove> moves, List<H2hUnfilledRelegation> unfilled})
  planAbsenceMoves({
    required List<H2hHeldSeat> elite,
    required List<H2hHeldSeat> extra,
    required List<H2hCountedRound> counted,
    required List<H2hCandidateFacts> facts,
    required Set<UserId> alreadyOut,
    required Set<UserId> alreadyIn,
    required bool Function(UserId relegated, H2hHeldSeat seat) wouldRepeat,
  }) {
    final ordered = List<H2hHeldSeat>.of(elite)
      ..sort((a, b) {
        final byGroup = a.groupIndex.compareTo(b.groupIndex);
        return byGroup != 0 ? byGroup : a.slot.compareTo(b.slot);
      });
    final due = <(H2hHeldSeat, List<H2hCountedRound>)>[
      for (final seat in ordered)
        if (!alreadyOut.contains(seat.userId))
          (seat, absenceRun(seat.userId, counted)),
    ].where((e) => e.$2.length >= relegationStreak).toList();

    final moves = <H2hPlannedMove>[];
    final unfilled = <H2hUnfilledRelegation>[];
    final taken = <UserId>{...alreadyOut, ...alreadyIn};
    for (final (seat, run) in due) {
      final chosen = chooseSubstitute(
        out: seat.userId,
        extra: extra,
        counted: counted,
        facts: facts,
        excluded: taken,
        wouldRepeat: wouldRepeat,
      );
      if (chosen == null) {
        unfilled.add(H2hUnfilledRelegation(out: seat.userId, eliteSeat: seat));
        continue;
      }
      taken
        ..add(seat.userId)
        ..add(chosen.$1.userId);
      moves.add(
        H2hPlannedMove(
          out: seat.userId,
          eliteSeat: seat,
          substitute: chosen.$1.userId,
          extraSeat: chosen.$2,
          facts: chosen.$1,
          absentRounds: run,
        ),
      );
    }
    return (
      moves: List<H2hPlannedMove>.unmodifiable(moves),
      unfilled: List<H2hUnfilledRelegation>.unmodifiable(unfilled),
    );
  }

  /// The best substitute for [out] among the holders of [extra] seats, with
  /// the seat he leaves, or null when none qualifies.
  static (H2hCandidateFacts, H2hHeldSeat)? chooseSubstitute({
    required UserId out,
    required List<H2hHeldSeat> extra,
    required List<H2hCountedRound> counted,
    required List<H2hCandidateFacts> facts,
    required Set<UserId> excluded,
    required bool Function(UserId relegated, H2hHeldSeat seat) wouldRepeat,
  }) {
    final seatOf = <UserId, H2hHeldSeat>{
      for (final seat in extra) seat.userId: seat,
    };
    final ranked = rankCandidates(
      facts: [
        for (final f in facts)
          if (seatOf.containsKey(f.userId)) f,
      ],
      counted: counted,
      excluded: {...excluded, out},
    );
    for (final candidate in ranked) {
      final seat = seatOf[candidate.userId]!;
      if (!wouldRepeat(out, seat)) {
        return (candidate, seat);
      }
    }
    return null;
  }
}
