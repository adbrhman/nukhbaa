import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: link a fixture to a season (Phase 7.4 — the per-fixture
/// sibling of [LinkFixtureToRound] now that a season no longer needs a
/// round to group fixtures through, Axiom 4 Amendment).
///
/// Establishes the M:N association Competition owns while keeping Football
/// Data decoupled (Axiom 3): the fixture is named by id only ([FixtureRef]),
/// never pulled into the aggregate. Admin-only.
///
/// Unlike [LinkFixtureToRound] there is no lifecycle status to gate against
/// (a season carries none) — the only precondition is that the season
/// exists. `displayOrder` is caller-supplied, exactly as
/// [LinkFixtureToRound] does it.
///
/// Never throws; returns a typed [Result].
final class LinkFixtureToSeason {
  /// Creates the use-case over its repositories.
  const LinkFixtureToSeason({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
  }) : _competitions = competitionRepository,
       _fixturePredictions = fixturePredictionRepository;

  final CompetitionRepository _competitions;
  final FixturePredictionRepository _fixturePredictions;

  /// Links [fixtureId] into [seasonId] at presentation position
  /// [displayOrder].
  Future<Result<SeasonFixture>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required int displayOrder,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }

    // The season must exist.
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }

    final linkResult = SeasonFixture.create(
      seasonId: sId,
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      displayOrder: displayOrder,
    );
    if (linkResult is Err<SeasonFixture>) {
      return Result.err(linkResult.error);
    }
    final link = (linkResult as Ok<SeasonFixture>).value;

    final saved = await _fixturePredictions.linkFixtureToSeason(link);
    return switch (saved) {
      Ok<void>() => Result.ok(link),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
