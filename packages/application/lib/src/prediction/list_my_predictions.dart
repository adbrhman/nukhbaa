import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/prediction_repository.dart';
import 'package:application/src/prediction/prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's own aggregated **prediction history** — every
/// prediction [principal] has ever submitted, across every round and every
/// season they have participated in (Application ADR §2: query separated from
/// command; mirrors [ListRoundPredictions], but scoped to the caller's own
/// forecasts across time rather than one round's whole pool).
///
/// **Visibility:** always the caller's OWN predictions, regardless of round
/// status — a user may always see their own submitted forecasts, unlike
/// [ListRoundPredictions] (which requires the round to be locked before
/// revealing the whole pool to fellow participants). There is no
/// season-membership gate to check here either: the repository already scopes
/// to `principal.userId`, so nothing here can reveal another user's
/// prediction.
///
/// Never throws; returns a typed [Result].
final class ListMyPredictions {
  /// Creates the use-case over its collaborator.
  const ListMyPredictions({required PredictionRepository predictionRepository})
    : _predictions = predictionRepository;

  final PredictionRepository _predictions;

  /// Lists every prediction [principal] has ever submitted, newest first.
  Future<Result<List<PredictionView>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _predictions.listByUser(principal.userId);
  }
}
