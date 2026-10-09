import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_league_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A day an admin may approve next.
final class H2hCandidateDay {
  /// Creates a candidate.
  const H2hCandidateDay({required this.fixtures, required this.kind});

  /// The day and its fixtures.
  final H2hDayFixtures fixtures;

  /// Regular (six or more) or fill (five).
  final H2hRoundKind kind;
}

/// The admin's view of a month's rounds.
final class H2hRoundsOverview {
  /// Creates an overview.
  const H2hRoundsOverview({
    required this.monthStart,
    required this.month,
    required this.rounds,
    required this.candidates,
  });

  /// The first day of the month, as a UTC midnight.
  final DateTime monthStart;

  /// The month's draw, or null when it was not drawn yet.
  final H2hMonthInfo? month;

  /// The approved rounds, in order.
  final List<H2hRound> rounds;

  /// The days after the last round, not started yet, that may become the
  /// next round, in date order. Empty once the month holds 19 rounds.
  final List<H2hCandidateDay> candidates;
}

/// Use-case: an admin reads a month's rounds and the days that may be
/// approved next (migration 0100).
///
/// Never throws; returns a typed [Result].
final class ListH2hRounds {
  /// Creates the use-case over its collaborators.
  const ListH2hRounds({
    required H2hRoundStore rounds,
    required H2hLeagueStore leagues,
    required Clock clock,
  }) : _rounds = rounds,
       _leagues = leagues,
       _clock = clock;

  final H2hRoundStore _rounds;
  final H2hLeagueStore _leagues;
  final Clock _clock;

  /// Reads the month containing [day] (today when null) for [principal], an
  /// admin.
  Future<Result<H2hRoundsOverview>> call({
    required AuthenticatedUser principal,
    DateTime? day,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final now = _clock.nowUtc();
    final today = riyadhDayOf(now);
    final month = H2hLeaguePolicy.monthStartOf(day ?? today);

    final infoResult = await _leagues.monthOf(month);
    if (infoResult is Err<H2hMonthInfo?>) {
      return Result.err(infoResult.error);
    }
    final listResult = await _rounds.roundsOf(month);
    if (listResult is Err<List<H2hRound>>) {
      return Result.err(listResult.error);
    }
    final rounds = (listResult as Ok<List<H2hRound>>).value;

    final candidates = <H2hCandidateDay>[];
    if (rounds.length < H2hLeaguePolicy.maxRounds) {
      final last = H2hLeaguePolicy.monthEndOf(
        month,
      ).subtract(const Duration(days: 1));
      final afterRounds = rounds.isEmpty
          ? month
          : rounds.last.day.add(const Duration(days: 1));
      final from = afterRounds.isAfter(today) ? afterRounds : today;
      if (!from.isAfter(last)) {
        final daysResult = await _rounds.daysBetween(from: from, through: last);
        if (daysResult is Err<List<H2hDayFixtures>>) {
          return Result.err(daysResult.error);
        }
        for (final fixtures in (daysResult as Ok<List<H2hDayFixtures>>).value) {
          final kind = H2hLeaguePolicy.roundKindOf(fixtures.fixtureCount);
          final firstKickoff = fixtures.firstKickoff;
          if (kind == null ||
              firstKickoff == null ||
              !now.isBefore(firstKickoff)) {
            continue;
          }
          candidates.add(H2hCandidateDay(fixtures: fixtures, kind: kind));
        }
      }
    }

    return Result.ok(
      H2hRoundsOverview(
        monthStart: month,
        month: (infoResult as Ok<H2hMonthInfo?>).value,
        rounds: rounds,
        candidates: candidates,
      ),
    );
  }
}
