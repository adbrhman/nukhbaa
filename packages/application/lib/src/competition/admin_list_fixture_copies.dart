import 'package:application/src/competition/ports/fixture_merger.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin read: a fixture and the other copies of its match
/// (`GET /admin/fixtures/{id}/copies`, migration 0176, script 95), each
/// with its predictions, doubles, result and provider link, so the admin
/// picks the copy to keep before merging ([AdminMergeFixtureCopies]).
///
/// The fixture itself comes first; a copy already merged is left out.
///
/// Never throws.
final class AdminListFixtureCopies {
  /// Creates the read over [merger].
  const AdminListFixtureCopies({required FixtureMerger merger})
    : _merger = merger;

  final FixtureMerger _merger;

  /// The copies of [fixtureId]'s match, for admin [principal].
  Future<Result<List<FixtureCopy>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final fixture = FixtureRef.tryParse(fixtureId);
    if (fixture is Err<FixtureRef>) {
      return Result.err(fixture.error);
    }
    return _merger.copiesOf((fixture as Ok<FixtureRef>).value);
  }
}
