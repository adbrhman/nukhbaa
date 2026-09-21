/// Use-case: read the caller's own badges.
library;

import 'package:application/src/gamification/ports/player_badge_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One catalog badge as the caller stands on it (P2-8).
final class MyBadge {
  /// Creates a line of the badge wall.
  const MyBadge({
    required this.code,
    required this.current,
    required this.unlockedAt,
  });

  /// The catalog badge.
  final BadgeCode code;

  /// How far the caller has come, capped at [target] so a finished badge
  /// reads "25 of 25", never "31 of 25".
  final int current;

  /// When the badge was granted, or null while it is not held.
  final DateTime? unlockedAt;

  /// The count at which the badge is earned.
  int get target => code.target;
}

/// Lists every catalog badge, in catalog order, with the caller's progress
/// and the moment each held badge was granted (P2-8).
///
/// Held means a `badge_unlocked` event exists; the grant itself is the
/// evaluator's job, on its own schedule. A badge whose count is already
/// reached but whose event is not yet written is shown at full progress and
/// not held, and becomes held on the evaluator's next run.
///
/// Only the caller's own badges, always: there is no surface for reading
/// someone else's, so the principal is the whole of the authority check.
///
/// Never throws; returns a typed [Result].
final class GetMyBadges {
  /// Creates the use-case over its reader.
  const GetMyBadges({required PlayerBadgeReader badges}) : _badges = badges;

  final PlayerBadgeReader _badges;

  /// Reads [principal]'s badge wall.
  Future<Result<List<MyBadge>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final recordResult = await _badges.recordOf(principal.userId);
    if (recordResult is Err<PlayerBadgeRecord>) {
      return Result.err(recordResult.error);
    }
    final record = (recordResult as Ok<PlayerBadgeRecord>).value;

    return Result.ok(
      List<MyBadge>.unmodifiable(<MyBadge>[
        for (final code in BadgeCode.values)
          MyBadge(
            code: code,
            current: _capped(code.countIn(record.progress), code.target),
            unlockedAt: record.unlockedAt[code],
          ),
      ]),
    );
  }

  static int _capped(int count, int target) => count > target ? target : count;
}
