import 'package:application/src/football_data/ports/team_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the full Football Data team catalog (`GET /teams`), so a
/// client can resolve a fixture's [FixtureSchedule.homeTeamId]/[awayTeamId]
/// into a display name + crest without hardcoding either client-side.
///
/// Read-only, no side effect. Any authenticated user may browse it (mirrors
/// every other client-facing catalog read, e.g. [ListCompetitions]) — a team
/// carries no visibility/ownership concept of its own.
final class ListTeams {
  /// Creates the use-case over its [repository].
  const ListTeams({required TeamRepository repository})
    : _repository = repository;

  final TeamRepository _repository;

  /// Lists every known team, visible to [principal].
  Future<Result<List<Team>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _repository.listAll();
  }
}
