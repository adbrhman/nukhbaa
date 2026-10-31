/// Read/write port for the podium of a crowned month: its second and third
/// places (migration 0191).
///
/// The adapter stores and reads; who stands on the podium is the
/// use-case's (`AdminSetMonthPodium`). The database triggers are only the
/// backstop: a crowned month, never its champion, a player of it.
///
/// General contract: MUST NOT throw; infrastructure failures are
/// [ErrorKind.transient].
library;

import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One place to set, with the final figures frozen as they stood.
final class PodiumPlaceToSet {
  /// Creates the row.
  const PodiumPlaceToSet({
    required this.place,
    required this.userId,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
  });

  /// 2 or 3.
  final int place;

  /// The player.
  final UserId userId;

  /// Prediction points on the final board.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures (the accuracy's denominator).
  final int decidedCount;
}

/// A podium place as it is read back.
final class MonthPodiumPlace {
  /// Creates the record.
  const MonthPodiumPlace({
    required this.seasonId,
    required this.place,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    this.photoUpdatedAt,
    this.avatarUpdatedAt,
  });

  /// The month.
  final SeasonId seasonId;

  /// 2 or 3.
  final int place;

  /// The player.
  final UserId userId;

  /// The player's current display name.
  final String displayName;

  /// Prediction points on the final board.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures.
  final int decidedCount;

  /// When the celebration picture was set (UTC), or null without one.
  final DateTime? photoUpdatedAt;

  /// When the player's own profile picture was set (UTC), or null.
  final DateTime? avatarUpdatedAt;
}

/// The podium store.
abstract interface class MonthPodiumRepository {
  /// The podium places, newest month first, then by place; at most [limit]
  /// rows.
  Future<Result<List<MonthPodiumPlace>>> list({required int limit});

  /// The podium of [season], by place; empty when it is not set.
  Future<Result<List<MonthPodiumPlace>>> of(SeasonId season);

  /// Sets the podium of [season] in one transaction. A database refusal
  /// (not crowned, a champion, not a player, already set) is an
  /// [ErrorKind.invariant] error `champion.podium_refused`.
  Future<Result<void>> set({
    required SeasonId season,
    required List<PodiumPlaceToSet> places,
    required UserId setBy,
    required DateTime setAt,
  });
}
