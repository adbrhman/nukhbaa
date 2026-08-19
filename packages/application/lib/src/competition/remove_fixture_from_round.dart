import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: remove a fixture from a round (Application ADR, Section 2:
/// command intent `RemoveFixtureFromRound`) — the counterpart of
/// [LinkFixtureToRound], for correcting a duplicate/mistaken link before the
/// round moves on. Admin-only.
///
/// Business invariants enforced here (mirrors [LinkFixtureToRound]'s own
/// checks, so a removal is only ever legal exactly where an equivalent add
/// still would be):
///   * The round must still be [RoundStatus.open] — once locked its
///     composition is frozen along with its ruleset, same rule as linking.
///   * The fixture must **not already carry a recorded result**
///     ([FixtureResultRepository.findByFixture]) — once a result exists,
///     removing the link would silently drop scored data instead of
///     correcting an unscored mistake, so this is rejected as
///     [ErrorKind.invariant] `competition.fixture_result_already_recorded`.
///
/// The delete itself is idempotent at the storage layer
/// ([CompetitionRepository.deleteRoundFixture]); a link that no longer exists
/// is treated as already-removed rather than an error, so a retried remove
/// converges.
///
/// Never throws; returns a typed [Result].
final class RemoveFixtureFromRound {
  /// Creates the use-case over its collaborators.
  const RemoveFixtureFromRound({
    required CompetitionRepository competitionRepository,
    required FixtureResultRepository fixtureResultRepository,
  }) : _competition = competitionRepository,
       _fixtureResults = fixtureResultRepository;

  final CompetitionRepository _competition;
  final FixtureResultRepository _fixtureResults;

  /// Removes [fixtureId] from [roundId]. Returns `Ok(true)` when a link was
  /// actually removed, `Ok(false)` when there was nothing to remove (already
  /// gone — idempotent, mirrors `RemoveReaction`).
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String roundId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final roundIdResult = RoundId.tryParse(roundId);
    if (roundIdResult is Err<RoundId>) {
      return Result.err(roundIdResult.error);
    }
    final rId = (roundIdResult as Ok<RoundId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    // The round must exist and still be open.
    final roundResult = await _competition.findRound(rId);
    if (roundResult is Err<Round>) {
      return Result.err(roundResult.error);
    }
    final round = (roundResult as Ok<Round>).value;
    if (!round.status.isOpen) {
      return Result.err(
        AppError.invariant(
          'competition.round_not_open_for_linking',
          'Fixtures can only be removed while the round is open '
              '(round is ${round.status.wireValue})',
        ),
      );
    }

    // A fixture with a recorded result has already been scored/could be
    // scored — removing it here would silently orphan that result rather
    // than correct a genuine mistake.
    final existingResult = await _fixtureResults.findByFixture(fixture);
    if (existingResult is Err<FixtureResult?>) {
      return Result.err(existingResult.error);
    }
    if ((existingResult as Ok<FixtureResult?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'competition.fixture_result_already_recorded',
          'This fixture already has a recorded result and can no longer '
              'be removed from the round',
        ),
      );
    }

    final deleted = await _competition.deleteRoundFixture(
      roundId: rId,
      fixture: fixture,
    );
    return deleted;
  }
}
