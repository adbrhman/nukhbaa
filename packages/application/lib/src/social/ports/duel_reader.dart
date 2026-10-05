import 'package:application/src/social/duel_views.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read side of Duels (migration 0090): the projections the screens need.
///
/// Reads only. Every write goes through `DuelChallengeRepository` and the
/// 0090 functions. Nothing returned here is masked; the use-cases decide
/// what a caller may see.
abstract interface class DuelReader {
  /// The challenge with share [code], or `Ok(null)` when there is none.
  Future<Result<DuelChallengePreview?>> findChallengeByCode(DuelCode code);

  /// Open challenges [userId] created or was privately invited to, whose
  /// fixture kicks off after [now] and which still have a free seat,
  /// soonest kickoff first, at most [limit].
  Future<Result<List<DuelChallengePreview>>> listOpenChallengesFor({
    required UserId userId,
    required DateTime now,
    required int limit,
  });

  /// Duels [userId] plays in whose fixture kicks off at or after [since],
  /// newest kickoff first, at most [limit].
  Future<Result<List<DuelRecord>>> listDuelsFor({
    required UserId userId,
    required DateTime since,
    required int limit,
  });
}
