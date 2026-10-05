import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/duel_views.dart';
import 'package:application/src/social/ports/duel_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: open a shared duel link.
///
/// Answers the challenge behind a share code with its derived state, so the
/// invited player sees who challenged them, on which fixture, and whether
/// the invitation can still be taken. No prediction is ever part of it.
final class GetDuelChallengeByCode {
  /// Creates the use-case.
  const GetDuelChallengeByCode({
    required DuelReader duels,
    required Clock clock,
  }) : _duels = duels,
       _clock = clock;

  final DuelReader _duels;
  final Clock _clock;

  /// Resolves [code] for [principal].
  Future<Result<DuelChallengeView>> call({
    required AuthenticatedUser principal,
    required String code,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final codeResult = DuelCode.tryParse(code.trim().toUpperCase());
    if (codeResult is Err<DuelCode>) return Result.err(codeResult.error);

    final found = await _duels.findChallengeByCode(
      (codeResult as Ok<DuelCode>).value,
    );
    if (found is Err<DuelChallengePreview?>) return Result.err(found.error);
    final challenge = (found as Ok<DuelChallengePreview?>).value;
    if (challenge == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_not_found',
          'Duel challenge was not found',
        ),
      );
    }

    return Result.ok(
      DuelChallengeView(
        challenge: challenge,
        state: challenge.stateAt(_clock.nowUtc()),
        callerIsChallenger: challenge.challengerUserId == principal.userId,
        callerIsTarget: challenge.targetUserId == principal.userId,
      ),
    );
  }
}
