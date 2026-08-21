library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';
import '../../core/providers.dart';

part 'round_scores_providers.g.dart';

/// `GET /rounds/{id}/scores` — every participant's computed score for a
/// scored round. Returns `null` (not an error) when the round has not been
/// scored yet (`scoring.round_not_scored`) — the caller shows no grade badge
/// in that case instead of an error state.
@riverpod
Future<RoundScoresDto?> roundScores(Ref ref, String roundId) async {
  final CompetitionApi api = ref.watch(competitionApiProvider);
  final result = await api.getRoundScores(roundId);
  return switch (result) {
    Ok<RoundScoresDto>(:final value) => value,
    Err<RoundScoresDto>(:final error)
        when error.code == 'scoring.round_not_scored' =>
      null,
    Err<RoundScoresDto>(:final error) => throw error,
  };
}
