library;

import 'dart:async';

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
  // A visible locked card keeps this provider watched, so a keepAlive timer
  // cannot make an already-returned empty/pending value refresh by itself.
  // Re-read only while scoring is still pending; once a real grade exists,
  // polling stops. When the card leaves the tree, auto-dispose cancels the
  // pending retry automatically.
  const retryDelay = Duration(minutes: 2);

  final CompetitionApi api = ref.watch(competitionApiProvider);
  final result = await api.getFixtureScores(
    seasonId: seasonId,
    fixtureId: fixtureId,
  );

  switch (result) {
    case Ok<FixtureScoresDto>(:final value):
      final waitingForScore =
          value.scores.isEmpty ||
          value.scores.every((score) => score.grade == 'pending');

      if (waitingForScore) {
        final retry = Timer(retryDelay, ref.invalidateSelf);
        ref.onDispose(retry.cancel);
      }
      return value;

    case Err<FixtureScoresDto>(:final error):
      throw error;
  }
}
