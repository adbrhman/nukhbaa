import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the admin **fixture-scores read**, bypassing the
/// participant-of-season visibility gate that [GetFixtureScores] enforces
/// (docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// [AdminGetRoundScores], added so an admin can investigate a user's
/// complaint on any fixture regardless of the admin's own season
/// membership).
///
/// Unlike [AdminGetRoundScores] (gated on the round being
/// `RoundStatus.scored`), this carries NO fixture-status gate — mirroring
/// [GetFixtureScores]'s Option-3 live/partial philosophy: an empty list
/// before the fixture has been scored is a legitimate result, not an error.
///
/// Never throws; returns a typed [Result].
final class AdminGetFixtureScores {
  /// Creates the use-case over its collaborator.
  const AdminGetFixtureScores({
    required FixtureScoreRepository fixtureScoreRepository,
  }) : _fixtureScores = fixtureScoreRepository;

  final FixtureScoreRepository _fixtureScores;

  /// Lists every participant's [ParticipantFixtureScore] for [fixtureId],
  /// visible to any [PlatformRole.admin] regardless of season membership.
  Future<Result<List<ParticipantFixtureScore>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    return _fixtureScores.listByFixture(fixture);
  }
}
