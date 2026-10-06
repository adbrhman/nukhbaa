/// The duels each player of a season won, shown beside their name on the
/// month's leaderboard (phase 1 of the plan).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

/// `GET /seasons/{id}/duel-wins`. A failed read leaves the board without
/// the marks rather than retrying behind it: they are an extra, never the
/// standings.
final seasonDuelWinsProvider = FutureProvider.autoDispose
    .family<SeasonDuelWinsDto, String>((ref, seasonId) async {
      final api = ref.watch(leaderboardsApiProvider);
      final result = await api.seasonDuelWins(seasonId);
      return switch (result) {
        Ok<SeasonDuelWinsDto>(:final value) => value,
        Err<SeasonDuelWinsDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);
