import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's own aggregated **fixture-prediction
/// history** — every per-fixture prediction [principal] has ever submitted,
/// across every fixture and every season they have participated in
/// (docs/project-context.md, Axiom 4 Amendment; the per-fixture sibling of
/// the retired round-level `ListMyPredictions` use-case, kept separate for
/// the same reason [FixturePredictionRepository] is its own port rather than
/// merged into [PredictionRepository]).
///
/// **Visibility:** always the caller's OWN predictions, regardless of fixture
/// status — a user may always see their own submitted forecasts. There is no
/// season-membership gate to check here: the repository already scopes to
/// `principal.userId`, so nothing here can reveal another user's prediction.
///
/// Never throws; returns a typed [Result].
final class ListMyFixturePredictions {
  /// Creates the use-case over its collaborator.
  const ListMyFixturePredictions({
    required FixturePredictionRepository fixturePredictionRepository,
  }) : _fixturePredictions = fixturePredictionRepository;

  final FixturePredictionRepository _fixturePredictions;

  /// Lists every fixture prediction [principal] has ever submitted, newest
  /// first.
  Future<Result<List<FixturePredictionView>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _fixturePredictions.listByUser(principal.userId);
  }
}
