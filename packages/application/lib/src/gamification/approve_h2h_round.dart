import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: an admin approves a day as the next round (migration 0100).
///
/// The day becomes the next round of its month when:
/// * it has not started -- its first fixture kicks off after now;
/// * it comes after the month's last approved round (rounds are numbered in
///   date order, so a round never moves another's number);
/// * the policy accepts it: six fixtures or more, or exactly five as an
///   admin's fill round, and fewer than 19 rounds so far.
///
/// The database refuses the same things again (Axiom 6), so a race between
/// two admins ends in one round, not two.
///
/// Never throws; returns a typed [Result] with the new round.
final class ApproveH2hRound {
  /// Creates the use-case over its collaborators.
  const ApproveH2hRound({
    required H2hRoundStore rounds,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _rounds = rounds,
       _ids = idGenerator,
       _clock = clock;

  final H2hRoundStore _rounds;
  final IdGenerator _ids;
  final Clock _clock;

  /// Approves the Riyadh [day] (any instant on that date) for [principal].
  Future<Result<H2hRound>> call({
    required AuthenticatedUser principal,
    required DateTime day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return approveDay(
      rounds: _rounds,
      ids: _ids,
      now: _clock.nowUtc(),
      day: DateTime.utc(day.year, day.month, day.day),
      approvedBy: principal.userId,
    );
  }

  /// Approves [day] as the next round of its month for [approvedBy], an
  /// admin, or for the system when null. Shared with `RunH2hRounds`.
  static Future<Result<H2hRound>> approveDay({
    required H2hRoundStore rounds,
    required IdGenerator ids,
    required DateTime now,
    required DateTime day,
    required UserId? approvedBy,
  }) async {
    final fixturesResult = await rounds.dayFixtures(day);
    if (fixturesResult is Err<H2hDayFixtures>) {
      return Result.err(fixturesResult.error);
    }
    final fixtures = (fixturesResult as Ok<H2hDayFixtures>).value;
    final firstKickoff = fixtures.firstKickoff;
    if (firstKickoff == null || !now.isBefore(firstKickoff)) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_day_started',
          'A round must be approved before its first match kicks off',
        ),
      );
    }

    final month = H2hLeaguePolicy.monthStartOf(day);
    final listResult = await rounds.roundsOf(month);
    if (listResult is Err<List<H2hRound>>) {
      return Result.err(listResult.error);
    }
    final list = (listResult as Ok<List<H2hRound>>).value;
    if (list.isNotEmpty && !day.isAfter(list.last.day)) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_out_of_order',
          'A round must come after the last approved round of its month',
        ),
      );
    }
    if (!H2hLeaguePolicy.canApprove(
      fixtureCount: fixtures.fixtureCount,
      approvedRounds: list.length,
      byAdmin: approvedBy != null,
    )) {
      return const Result.err(
        AppError.invariant(
          'h2h.round_not_eligible',
          'This day cannot be a round: too few matches or 19 rounds already',
        ),
      );
    }

    final idResult = H2hRoundId.tryParse(ids.newUuid());
    if (idResult is Err<H2hRoundId>) {
      return Result.err(idResult.error);
    }
    final round = H2hRound(
      id: (idResult as Ok<H2hRoundId>).value,
      monthStart: month,
      number: list.length + 1,
      day: day,
      fixtureCount: fixtures.fixtureCount,
      approvedBy: approvedBy,
      lockedAt: null,
    );
    final stored = await rounds.approve(
      id: round.id,
      monthStart: round.monthStart,
      number: round.number,
      day: round.day,
      fixtureCount: round.fixtureCount,
      approvedBy: round.approvedBy,
    );
    if (stored is Err<void>) {
      return Result.err(stored.error);
    }
    return Result.ok(round);
  }
}
