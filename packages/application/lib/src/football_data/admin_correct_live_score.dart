import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/ports/live_score_board.dart';
import 'package:application/src/football_data/ports/live_score_corrections.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin use-case: correct the running score of a match in play when the
/// provider has it wrong (a goal ruled out by VAR that the feed still
/// counts), or take a correction back.
///
/// A correction is laid over the provider's figure on the board players
/// read ([LiveScoreCorrection.applyTo]): the match card and the live points
/// change at once, and at full time the result sync records the corrected
/// score instead of the provider's. It is made against [_providerScores],
/// the provider's own figures, so it can only be made while the provider
/// reports the match; once the result is recorded the board has nothing to
/// correct.
///
/// Admin-only. Never throws; returns a typed [Result].
final class AdminCorrectLiveScore {
  /// Creates the use-case. [providerScores] is the board the provider poll
  /// writes, without corrections.
  const AdminCorrectLiveScore({
    required LiveScoreBoard providerScores,
    required LiveScoreCorrections corrections,
    required Clock clock,
  }) : _providerScores = providerScores,
       _corrections = corrections,
       _clock = clock;

  final LiveScoreBoard _providerScores;
  final LiveScoreCorrections _corrections;
  final Clock _clock;

  /// Sets [fixtureId]'s running score to [homeGoals]-[awayGoals], on behalf
  /// of the admin [principal]. Refused as [ErrorKind.invariant]
  /// `football_data.not_live` while the provider reports no running score
  /// for it.
  Result<LiveScoreCorrection> call({
    required AuthenticatedUser principal,
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
  }) {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;
    // The same goal bounds as a recorded result.
    final checked = FixtureResult.create(
      fixture: fixture,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
    );
    if (checked is Err<FixtureResult>) {
      return Result.err(checked.error);
    }

    final provider = _providerScores.read([fixture.value])[fixture.value];
    if (provider == null) {
      return Result.err(
        AppError.invariant(
          'football_data.not_live',
          'Fixture ${fixture.value} has no running score from the provider; '
              'record its result instead',
        ),
      );
    }
    final correction = LiveScoreCorrection(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      baseHomeGoals: provider.homeGoals,
      baseAwayGoals: provider.awayGoals,
      setAt: _clock.nowUtc(),
    );
    _corrections.set(fixture.value, correction);
    return Result.ok(correction);
  }

  /// Takes back the correction of [fixtureId], so the provider's figure
  /// shows and counts again. Clearing a fixture with no correction is not an
  /// error.
  Result<void> clear({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    _corrections.clear((fixtureResult as Ok<FixtureRef>).value.value);
    return const Result.ok(null);
  }
}
