import 'package:application/src/football_data/ports/league_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the full Football Data league catalog (`GET /leagues`), so
/// the admin fixture form can pick a league by name instead of leaving
/// `league_id` null -- which is what put 16 of 37 fixtures on screen labelled
/// with the month's competition name instead of their league.
///
/// Read-only, no side effect. Any authenticated user may browse it, mirroring
/// [ListTeams]: a league carries no visibility concept of its own.
final class ListLeagues {
  /// Creates the use-case over its [repository].
  const ListLeagues({required LeagueRepository repository})
    : _repository = repository;

  final LeagueRepository _repository;

  /// Lists every known league, visible to [principal].
  Future<Result<List<League>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _repository.listAll();
  }
}
