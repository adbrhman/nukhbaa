/// The Football Data team-catalog read — a single `FutureProvider` wrapping
/// `GET /teams` (`TeamsApi`, `core/providers.dart`'s `teamsApiProvider`).
///
/// This is the one model-backed source of team identity (name + crest) the
/// rest of the app resolves against, replacing the client-only
/// `team_registry.dart` lookup table wherever a fixture carries a resolved
/// `home_team_id`/`away_team_id` (`football_data.teams`, migration
/// `0024_fixture_schedule_team_ids.sql`). A fixture with no team id yet (an
/// older schedule row, or a league with no seeded catalog) still falls back
/// cleanly to `team_registry.dart`'s name-based lookup — see
/// `team_identity.dart`'s `resolveTeamIdentity`.
library;

import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'teams_providers.g.dart';

/// `GET /teams` — the full team catalog.
///
/// An empty catalog is a legitimate `Ok(<empty>)` — every screen that reads
/// this provider must degrade to the name-based fallback, never break.
@riverpod
Future<List<TeamDto>> teamCatalog(Ref ref) async {
  final api = ref.watch(teamsApiProvider);
  return switch (await api.listTeams()) {
    Ok<List<TeamDto>>(:final value) => value,
    Err<List<TeamDto>>(:final error) => throw error,
  };
}
