import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the seats left for absence in the last group that plays, and
/// their fills from the waiting list (NK278, migration 0214; December 2026
/// on).
///
/// Backed by `PostgresH2hVacancyStore`. It stores and reads; who leaves and
/// who takes the seat is `H2hAbsencePolicy.planDecemberMoves`. The database
/// refuses a player who moves twice before a round, one relegated twice in
/// a month or coming back up in it, a seat not held by the player who
/// leaves it, a fill of a seat that is not vacant or by a player who does
/// not hold a waiting seat, and a round that has started: every such
/// refusal is the invariant `h2h.move_refused`.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hVacancyStore {
  /// Every seat left for absence in the month opened by [monthStart],
  /// oldest first, with its fill when it has one.
  Future<Result<List<H2hSeatVacancy>>> vacanciesOf(DateTime monthStart);

  /// Stores [vacancy] and, with [fill], the fill of the same seat, in ONE
  /// transaction: both are stored or neither, so a player never loses his
  /// seat without the record that he left it for the waiting list, and a
  /// seat is never filled without its vacancy.
  Future<Result<void>> vacate({
    required H2hSeatVacancy vacancy,
    H2hVacancyFill? fill,
  });

  /// Stores the fill of a seat left vacant before.
  Future<Result<void>> fill(H2hVacancyFill fill);
}

/// A seat left for absence (`h2h_seat_vacancies`).
final class H2hSeatVacancy {
  /// Creates a vacancy.
  const H2hSeatVacancy({
    required this.id,
    required this.monthStart,
    required this.leagueId,
    required this.slot,
    required this.outUser,
    required this.fromRound,
    this.absentRounds = const <({DateTime month, int round})>[],
    this.filledBy,
    this.filledFrom,
  });

  /// The vacancy's id.
  final String id;

  /// The month, as a UTC midnight on its first day.
  final DateTime monthStart;

  /// The group of the seat.
  final H2hLeagueId leagueId;

  /// The seat's slot.
  final int slot;

  /// The player who left it for the waiting list.
  final UserId outUser;

  /// The first round the seat is vacant.
  final int fromRound;

  /// The rounds he missed in a row.
  final List<({DateTime month, int round})> absentRounds;

  /// The player of the waiting list who took it, or null: still vacant.
  final UserId? filledBy;

  /// The first round he plays in it.
  final int? filledFrom;

  /// Whether a player took the seat.
  bool get filled => filledBy != null;
}

/// A vacant seat taken by a player of the waiting list
/// (`h2h_vacancy_fills`).
final class H2hVacancyFill {
  /// Creates a fill.
  const H2hVacancyFill({
    required this.vacancyId,
    required this.monthStart,
    required this.inUser,
    required this.fromRound,
    required this.fromLeagueId,
    required this.fromSlot,
    this.facts,
  });

  /// The vacancy filled.
  final String vacancyId;

  /// The month, as a UTC midnight on its first day.
  final DateTime monthStart;

  /// The player who takes the seat.
  final UserId inUser;

  /// The first round he plays in it.
  final int fromRound;

  /// The waiting group he leaves.
  final H2hLeagueId fromLeagueId;

  /// The waiting seat he leaves.
  final int fromSlot;

  /// What he was chosen on.
  final H2hCandidateFacts? facts;
}
