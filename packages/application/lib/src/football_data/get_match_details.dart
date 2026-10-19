import 'package:application/src/football_data/ports/match_details.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the story of a finished match for its details page -- its
/// events with their minutes, the half-time score, the ground -- as
/// [SyncMatchDetails] read it from the provider. Null while it has not been
/// read yet. Any signed-in user may read it. Never throws.
final class GetMatchDetails {
  /// Creates the use-case.
  const GetMatchDetails({required MatchDetailsStore store}) : _store = store;

  final MatchDetailsStore _store;

  /// The details of [fixtureId] for [principal].
  Future<Result<MatchDetails?>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final fixture = FixtureRef.tryParse(fixtureId);
    if (fixture is Err<FixtureRef>) {
      return Result.err(fixture.error);
    }
    return _store.find((fixture as Ok<FixtureRef>).value.value);
  }
}
