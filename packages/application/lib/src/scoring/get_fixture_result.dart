/// Use-case: the recorded final score of one fixture, for display.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the actual final score recorded for a fixture -- the one scoring
/// compared every prediction against -- so a player's finished prediction
/// can show it under their call. `Ok(null)` until a result is recorded.
///
/// Read only: it never touches scoring, and scoring never depends on it.
/// Never throws; returns a typed [Result].
final class GetFixtureResult {
  /// Creates the use-case over its port.
  const GetFixtureResult({required FixtureResultRepository results})
    : _results = results;

  final FixtureResultRepository _results;

  /// The recorded result of [fixtureId], or `Ok(null)` when there is none.
  Future<Result<FixtureResult?>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final ref = FixtureRef.tryParse(fixtureId);
    if (ref is Err<FixtureRef>) {
      return Result.err(ref.error);
    }
    return _results.findByFixture((ref as Ok<FixtureRef>).value);
  }
}
