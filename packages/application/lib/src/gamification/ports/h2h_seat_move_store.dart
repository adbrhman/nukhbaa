import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for relegation for absence in the head-to-head league (migration
/// 0189): the seat swaps, the rounds an admin excused, the warnings sent,
/// and the facts the absence job decides on.
///
/// Backed by `PostgresH2hSeatMoveStore`. It stores and reads; who is
/// relegated and who comes up is `H2hAbsencePolicy`, in Dart.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hSeatMoveStore {
  /// Every swap of the month opened by [monthStart], oldest first.
  Future<Result<List<H2hSeatMove>>> movesOf(DateTime monthStart);

  /// For each of [rounds]: when its last fixture still on its day kicks
  /// off, how many such fixtures it holds, and who predicted at least one
  /// of them. A round not locked yet is left out. The results do not
  /// matter: a prediction is a presence whatever happens to the match.
  Future<Result<List<H2hRoundAttendance>>> attendance(List<H2hRound> rounds);

  /// The excusals of [rounds], keyed by round.
  Future<Result<Map<H2hRoundId, H2hRoundExcusal>>> excusals(
    List<H2hRound> rounds,
  );

  /// The facts of [users] over the [H2hAbsencePolicy.windowDays] Riyadh
  /// days ending on [lastDay] (a UTC midnight): matches of their seasons
  /// missed, points, exact scorelines, days with a prediction. A user with
  /// no fixture in the window is read with zeros.
  Future<Result<List<H2hCandidateFacts>>> candidateFacts({
    required DateTime lastDay,
    required List<UserId> users,
  });

  /// Stores a swap and logs it in the admin log of 0101, in one
  /// transaction. A swap the database refuses (a player relegated or
  /// promoted twice, a seat changed twice for a round, a round already
  /// started, a relegated player coming back) is an [ErrorKind.invariant]
  /// error with code `h2h.move_refused`.
  Future<Result<void>> recordMove({
    required H2hSeatMove move,
    required String logId,
  });

  /// Takes [roundId] out of the absence count and logs it. False when it
  /// was excused already (nothing changes then).
  Future<Result<bool>> excuse({
    required H2hRoundId roundId,
    required String reason,
    required UserId by,
    required String logId,
  });

  /// Records the warning of [userId] after [roundId]; true when it is new,
  /// false when he was warned for that round already.
  Future<Result<bool>> recordWarning({
    required H2hRoundId roundId,
    required UserId userId,
  });

  /// The warnings sent for [rounds]: (round, user) pairs.
  Future<Result<List<({H2hRoundId roundId, UserId userId, DateTime at})>>>
  warningsOf(List<H2hRound> rounds);

  /// The push tokens of [userId]'s devices, when the account is active.
  Future<Result<List<String>>> pushTokensOf(UserId userId);
}

/// One round's attendance (see [H2hSeatMoveStore.attendance]).
final class H2hRoundAttendance {
  /// Creates an attendance.
  const H2hRoundAttendance({
    required this.roundId,
    required this.fixtures,
    required this.lastKickoff,
    required this.present,
  });

  /// The round.
  final H2hRoundId roundId;

  /// Its frozen fixtures still on its day, visible and real.
  final int fixtures;

  /// The last kickoff among them (UTC), or null when none is left.
  final DateTime? lastKickoff;

  /// The players who predicted at least one of them.
  final Set<UserId> present;
}

/// A round an admin took out of the absence count.
final class H2hRoundExcusal {
  /// Creates an excusal.
  const H2hRoundExcusal({
    required this.roundId,
    required this.reason,
    required this.by,
    required this.at,
  });

  /// The round.
  final H2hRoundId roundId;

  /// Why (the app was down, ...).
  final String reason;

  /// The admin.
  final UserId by;

  /// When.
  final DateTime at;
}

/// A seat swap (one row of `gamification.h2h_seat_moves`).
final class H2hSeatMove {
  /// Creates a swap.
  const H2hSeatMove({
    required this.id,
    required this.monthStart,
    required this.fromRound,
    required this.kind,
    required this.outUser,
    required this.inUser,
    required this.eliteLeagueId,
    required this.eliteSlot,
    required this.extraLeagueId,
    required this.extraSlot,
    required this.absentRounds,
    required this.facts,
    required this.reason,
    required this.decidedBy,
    required this.createdAt,
  });

  /// The swap's id.
  final String id;

  /// The first day of its month, as a UTC midnight.
  final DateTime monthStart;

  /// The first round played in the new seats.
  final int fromRound;

  /// Why.
  final H2hSeatMoveKind kind;

  /// The player who left the elite seat.
  final UserId outUser;

  /// The player who took it.
  final UserId inUser;

  /// The elite group.
  final H2hLeagueId eliteLeagueId;

  /// The elite seat.
  final int eliteSlot;

  /// The extra group the substitute left.
  final H2hLeagueId extraLeagueId;

  /// The extra seat, now [outUser]'s.
  final int extraSlot;

  /// The rounds [outUser] missed in a row: (month, round number).
  final List<({DateTime month, int round})> absentRounds;

  /// What the substitute was chosen on, when known.
  final H2hCandidateFacts? facts;

  /// The admin's reason for a move by hand.
  final String? reason;

  /// The admin who decided, or null for the system.
  final UserId? decidedBy;

  /// When it was stored.
  final DateTime createdAt;
}
