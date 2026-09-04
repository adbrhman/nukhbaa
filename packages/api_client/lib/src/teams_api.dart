import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Football Data team catalog of `apps/server`.
///
/// Wraps the one ratified route verbatim — no invented path:
///   * `GET /teams` -> `List<TeamDto>` (`routes/teams/index.dart`), the
///     previously-unwired `football_data.teams` schema, now the single
///     source of a team's display name + crest so a client can resolve a
///     fixture's `home_team_id`/`away_team_id` without hardcoding either
///     client-side.
///
/// Read-only, no side effect. Behind `bearerAuth` (`routes/teams/
/// _middleware.dart`); any authenticated user may call it. Never throws —
/// returns a typed [Result].
final class TeamsApi {
  /// Creates the teams client over the shared [ApiTransport].
  const TeamsApi(this._transport);

  final ApiTransport _transport;

  /// `GET /teams` — the full team catalog.
  ///
  /// An empty catalog is a legitimate `Ok(<empty list>)`, never an error.
  Future<Result<List<TeamDto>>> listTeams() {
    return _transport.getList<TeamDto>(
      '/teams',
      parseElement: TeamDto.fromJson,
    );
  }
}
