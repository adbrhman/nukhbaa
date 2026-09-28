/// Use-case: the admin sets or replaces a champion's celebration picture
/// (migration 0077). Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Stores [bytes] as the picture of a crowned champion. The picture follows
/// the avatar rules (`User.validateAvatar`: 512 KB, JPEG / PNG / WEBP); a
/// transparent PNG lets the app lay it over the leaderboard.
///
/// Never throws; returns a typed [Result].
final class AdminSetChampionPhoto {
  /// Creates the use-case over its store.
  const AdminSetChampionPhoto({
    required MonthChampionRepository champions,
    required Clock clock,
  }) : _champions = champions,
       _clock = clock;

  final MonthChampionRepository _champions;
  final Clock _clock;

  /// Runs the use-case for [principal]; answers the month's champions as
  /// they stand after the change.
  Future<Result<List<MonthChampion>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String userId,
    required List<int> bytes,
    required String mime,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final userResult = UserId.tryParse(userId);
    if (userResult is Err<UserId>) {
      return Result.err(userResult.error);
    }
    final validated = User.validateAvatar(bytes.length, mime);
    if (validated is Err<void>) {
      return Result.err(validated.error);
    }
    final season = (seasonResult as Ok<SeasonId>).value;
    final stored = await _champions.setPhoto(
      season: season,
      user: (userResult as Ok<UserId>).value,
      bytes: bytes,
      mime: mime,
      now: _clock.nowUtc(),
    );
    if (stored is Err<bool>) {
      return Result.err(stored.error);
    }
    if (!(stored as Ok<bool>).value) {
      return const Result.err(
        AppError.invariant(
          'champion.not_found',
          'هذا اللاعب ليس بطلًا لهذا الشهر',
        ),
      );
    }
    final listed = await _champions.list(limit: 50);
    if (listed is Err<List<MonthChampion>>) {
      return Result.err(listed.error);
    }
    return Result.ok(
      (listed as Ok<List<MonthChampion>>).value
          .where((champion) => champion.seasonId == season)
          .toList(growable: false),
    );
  }
}
