/// The Football Data league-catalog read — a single `FutureProvider`
/// wrapping `GET /leagues` (`LeaguesApi`, `core/providers.dart`'s
/// `leaguesApiProvider`).
///
/// The sibling of `teams_providers.dart`. A fixture names its league by id
/// (`fixture_schedules.league_id`, migration 0027); this is how a screen
/// turns that id into a name without hardcoding one, and how the admin
/// form offers the leagues to choose from.
library;

import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'leagues_providers.g.dart';

/// `GET /leagues` — the full league catalog.
///
/// An empty catalog is a legitimate `Ok(<empty>)`; every caller must
/// degrade to showing nothing to pick, never break.
@riverpod
Future<List<LeagueDto>> leagueCatalog(Ref ref) async {
  final api = ref.watch(leaguesApiProvider);
  return switch (await api.listLeagues()) {
    Ok<List<LeagueDto>>(:final value) => value,
    Err<List<LeagueDto>>(:final error) => throw error,
  };
}
