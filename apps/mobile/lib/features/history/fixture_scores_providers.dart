library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';
import '../../core/providers.dart';

part 'fixture_scores_providers.g.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/scores` — every participant's
/// computed score for a fixture (Axiom 4 Amendment; the per-fixture sibling
/// of `roundScores`). Unlike the round-scoped read, an unscored fixture is a
/// legitimate `Ok(<empty list>)` (Option-3 philosophy — see
/// `CompetitionApi.getFixtureScores`), never a `409` "not scored yet" like
/// the round-scoped read — so there is no null-conversion case to special-
/// case here. Any error (non-participant, unlinked fixture, transport) is
/// left to propagate as `AsyncError`; a caller that wants a silent
/// grade-badge fallback instead of surfacing the error reads `.value`
/// (`null` on error, same as while loading) — mirroring how
/// `_FixturePredictionCard` already tolerates an unresolved
/// `roundFixturesProvider`/`roundScoresProvider`.
@riverpod
Future<FixtureScoresDto> fixtureScores(
  Ref ref,
  String seasonId,
  String fixtureId,
) async {
  final CompetitionApi api = ref.watch(competitionApiProvider);
  final result = await api.getFixtureScores(
    seasonId: seasonId,
    fixtureId: fixtureId,
  );
  return switch (result) {
    Ok<FixtureScoresDto>(:final value) => value,
    Err<FixtureScoresDto>(:final error) => throw error,
  };
}
