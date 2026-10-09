import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the rounds of the head-to-head league (migration 0100).
///
/// Backed by `PostgresH2hRoundStore`. Whether a day may become a round is
/// `H2hLeaguePolicy.canApprove`; the database is the backstop that keeps
/// rounds in date order, at most 19 a month, and withdrawals to the last
/// round that is not locked.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class H2hRoundStore {
  /// The approved rounds of the month opened by [monthStart], in order.
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart);

  /// The visible, non-test fixtures of the Riyadh [day] (a UTC midnight):
  /// how many there are and when the first kicks off.
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day);

  /// [dayFixtures] for every Riyadh day from [from] through [through] that
  /// holds at least one fixture, in date order.
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  });

  /// Stores an approved round. A database refusal (out of order, more than
  /// 19, a day already taken) is returned as an [ErrorKind.invariant]
  /// error.
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  });

  /// Withdraws [roundId]. Only the last round of a month, and only while it
  /// is not locked; otherwise an [ErrorKind.invariant] error.
  Future<Result<void>> withdraw(H2hRoundId roundId);

  /// Freezes the fixture list of [roundId]: every visible, non-test fixture
  /// of [day] at this moment. Idempotent; returns the frozen count.
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  });
}

/// One approved round.
final class H2hRound {
  /// Creates a round.
  const H2hRound({
    required this.id,
    required this.monthStart,
    required this.number,
    required this.day,
    required this.fixtureCount,
    required this.approvedBy,
    required this.lockedAt,
  });

  /// The round.
  final H2hRoundId id;

  /// The first day of its month, as a UTC midnight.
  final DateTime monthStart;

  /// 1-based number in the month.
  final int number;

  /// The Riyadh day of its fixtures, as a UTC midnight.
  final DateTime day;

  /// Fixtures the day held when the round was approved; once locked, the
  /// frozen count.
  final int fixtureCount;

  /// The admin who approved it, or null when the system did.
  final UserId? approvedBy;

  /// When its fixture list was frozen, or null while it is not.
  final DateTime? lockedAt;

  /// Whether the fixture list is frozen.
  bool get locked => lockedAt != null;

  /// The round as the policy sees it.
  H2hRoundRef get ref => H2hRoundRef(number: number, day: day);
}

/// The fixtures of one Riyadh day.
final class H2hDayFixtures {
  /// Creates a day.
  const H2hDayFixtures({
    required this.day,
    required this.fixtureCount,
    required this.firstKickoff,
  });

  /// The Riyadh day, as a UTC midnight.
  final DateTime day;

  /// Visible, non-test fixtures of the day.
  final int fixtureCount;

  /// When the first of them kicks off, or null when there is none.
  final DateTime? firstKickoff;
}
