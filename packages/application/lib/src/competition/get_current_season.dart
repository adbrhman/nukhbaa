import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: resolve the single "current" monthly season of a
/// competition (Application ADR, Section 2: query separated from command).
///
/// The domain carries no `status`/`isActive` field on [CompetitionSeason] --
/// "current" is always computed fresh against "now" via [Clock] and
/// [CompetitionSeason.isCurrentAt], the same "computed, never stored"
/// principle `FixtureLock` already establishes for fixture locking
/// (docs/project-context.md). There is no persisted "current season" state
/// to drift out of sync.
///
/// A month with no season yet created by the admin -- an operational gap
/// between months -- is a legitimate `Ok(null)`, never an error: the caller
/// (e.g. the client's home screen) is expected to render an explicit empty
/// state for "no active season right now", not treat it as a fault.
///
/// The caller must be an authenticated user (`PlatformRole.user`, matching
/// every other client-facing read).
///
/// Never throws; returns a typed [Result].
final class GetCurrentSeason {
  /// Creates the use-case over its collaborators.
  const GetCurrentSeason({
    required CompetitionRepository repository,
    required Clock clock,
  }) : _competition = repository,
       _clock = clock;

  final CompetitionRepository _competition;
  final Clock _clock;

  /// Resolves the current season of [competitionId], visible to [principal].
  Future<Result<CompetitionSeason?>> call({
    required AuthenticatedUser principal,
    required String competitionId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final idResult = CompetitionId.tryParse(competitionId);
    if (idResult is Err<CompetitionId>) {
      return Result.err(idResult.error);
    }

    return _competition.findCurrentSeason(
      competitionId: (idResult as Ok<CompetitionId>).value,
      nowUtc: _clock.nowUtc(),
    );
  }
}
