/// The reactions on the predictions of one fixture (migration 0094), read
/// for the predictions board and its reaction sheet.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import 'fixture_prediction_providers.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/reactions`: one tally per
/// prediction that received any reaction, with the viewer's own. The same
/// kickoff gate as the predictions themselves; read only while the board
/// is open.
final predictionReactionsProvider = FutureProvider.autoDispose
    .family<PredictionReactionsDto, FixturePredictionDistributionKey>((
      ref,
      key,
    ) async {
      final api = ref.watch(predictionApiProvider);
      final result = await api.listPredictionReactions(
        seasonId: key.seasonId,
        fixtureId: key.fixtureId,
      );
      return switch (result) {
        Ok<PredictionReactionsDto>(:final value) => value,
        Err<PredictionReactionsDto>(:final error) => throw error,
      };
      // A refused or failed read shows the board without reactions at once
      // instead of retrying behind it.
    }, retry: (_, _) => null);
