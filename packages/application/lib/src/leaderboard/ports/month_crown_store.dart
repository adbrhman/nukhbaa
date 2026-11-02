/// Read/write port for the month's automatic crowning (migration 0199,
/// script 204): which months to look at, where each stands, the prize set
/// ahead for it, and what the owner was already told.
///
/// The adapter stores and reads; when to crown is `AutoCrownMonths`'. The
/// database functions only report.
///
/// General contract: MUST NOT throw; infrastructure failures are
/// [ErrorKind.transient].
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A monthly contest that ended a short while ago.
final class CrownDueMonth {
  /// Creates the month.
  const CrownDueMonth({
    required this.seasonId,
    required this.label,
    required this.endAt,
    this.crownedAt,
  });

  /// The contest.
  final SeasonId seasonId;

  /// Its label (`11/2026`).
  final String label;

  /// When it closed (UTC, exclusive).
  final DateTime endAt;

  /// When it was crowned (UTC), or null while it is not.
  final DateTime? crownedAt;
}

/// Where a month stands for its crowning, over the fixtures its board sums.
final class MonthCrownState {
  /// Creates the state.
  const MonthCrownState({
    required this.waiting,
    required this.skipped,
    required this.rescore,
    this.waitingNames,
    this.skippedNames,
    this.lastResultAt,
  });

  /// Matches without a result that may still be played or still have their
  /// result coming: the crowning waits for them.
  final int waiting;

  /// Their names, by kickoff (the first ten).
  final String? waitingNames;

  /// Matches without a result that do not count: postponed or cancelled.
  final int skipped;

  /// Their names, by kickoff (the first ten).
  final String? skippedNames;

  /// The latest write of any of the month's results (UTC), or null.
  final DateTime? lastResultAt;

  /// Results whose points are not all in yet.
  final int rescore;
}

/// The store behind the automatic crowning.
abstract interface class MonthCrownStore {
  /// The monthly contests that ended within [window] before [now], oldest
  /// first.
  Future<Result<List<CrownDueMonth>>> dueMonths({
    required DateTime now,
    required Duration window,
  });

  /// Where [season] stands at [now]; a match without a result counts as
  /// postponed [postponedAfter] after its kickoff.
  Future<Result<MonthCrownState>> stateOf({
    required SeasonId season,
    required DateTime now,
    required Duration postponedAfter,
  });

  /// The results of [season] whose points are not all in (at most 50).
  Future<Result<List<FixtureRef>>> toRescore(SeasonId season);

  /// The prize to crown [season] with: the one set ahead for it, else the
  /// previous month's; null when there is none.
  Future<Result<String?>> prizeFor(SeasonId season);

  /// Sets or replaces the prize of [season] ahead of its crowning. Refused
  /// once it is crowned (`champion.already_crowned`), and for a month that
  /// does not exist (`champion.month_not_found`).
  Future<Result<void>> setPrize({
    required SeasonId season,
    required String prize,
    required UserId setBy,
    required DateTime setAt,
  });

  /// Records that the owner is told [kind] / [signature] about [season]:
  /// `Ok(true)` the first time, `Ok(false)` when he already was.
  Future<Result<bool>> noteOnce({
    required SeasonId season,
    required String kind,
    required String signature,
  });

  /// The latest write of a result of [season] made after [since], or null
  /// when there is none (or the month was crowned by hand before 0199).
  Future<Result<DateTime?>> resultsWrittenAfter({
    required SeasonId season,
    required DateTime since,
  });
}
