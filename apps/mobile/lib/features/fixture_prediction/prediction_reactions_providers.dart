/// The reactions on the predictions of one fixture (migration 0094), read
/// for the predictions board and its reaction sheet, and the viewer's own
/// changes to them: shown at once, saved after, put back if refused.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import 'fixture_prediction_providers.dart';

/// `GET /seasons/{id}/fixtures/{fixtureId}/reactions`: one tally per
/// prediction that received any reaction, with the viewer's own. The same
/// kickoff gate as the predictions themselves; read only while the board
/// is open. [PredictionReactions.choose] changes the viewer's reaction.
final predictionReactionsProvider = AsyncNotifierProvider.autoDispose
    .family<
      PredictionReactions,
      PredictionReactionsDto,
      FixturePredictionDistributionKey
    >(
      PredictionReactions.new,
      // A refused or failed read shows the board without reactions at once
      // instead of retrying behind it.
      retry: (_, _) => null,
    );

/// The reactions on one fixture's predictions.
class PredictionReactions extends AsyncNotifier<PredictionReactionsDto> {
  /// Creates the reactions of [arg]'s fixture.
  PredictionReactions(this.arg);

  /// The fixture (Riverpod 3 passes the family argument to the
  /// constructor).
  final FixturePredictionDistributionKey arg;

  @override
  Future<PredictionReactionsDto> build() async {
    final api = ref.watch(predictionApiProvider);
    final result = await api.listPredictionReactions(
      seasonId: arg.seasonId,
      fixtureId: arg.fixtureId,
    );
    return switch (result) {
      Ok<PredictionReactionsDto>(:final value) => value,
      Err<PredictionReactionsDto>(:final error) => throw error,
    };
  }

  /// Gives [kind] to [participantId]'s prediction, or takes the viewer's
  /// reaction back when [kind] is null. The tallies change at once, the
  /// server is asked after, and a refusal puts them back. True once saved.
  Future<bool> choose(String participantId, String? kind) async {
    final PredictionReactionsDto? before = state.value;
    if (before != null) {
      state = AsyncData(withViewerReaction(before, participantId, kind));
    }
    final api = ref.read(predictionApiProvider);
    final Result<bool> result = kind == null
        ? await api.removePredictionReaction(
            seasonId: arg.seasonId,
            fixtureId: arg.fixtureId,
            participantId: participantId,
          )
        : await api.reactToPrediction(
            seasonId: arg.seasonId,
            fixtureId: arg.fixtureId,
            participantId: participantId,
            kind: kind,
          );
    final bool saved = result is Ok<bool>;
    if (!ref.mounted) return saved;
    if (!saved && before != null) {
      state = AsyncData(before);
    } else if (saved && before == null) {
      // Nothing was shown ahead of the server: read what it holds now.
      ref.invalidateSelf();
    }
    return saved;
  }
}

/// [reactions] with the viewer's reaction on [participantId]'s prediction
/// set to [kind] (null: none): the old one counted out, the new one in.
PredictionReactionsDto withViewerReaction(
  PredictionReactionsDto reactions,
  String participantId,
  String? kind,
) {
  final PredictionReactionTallyDto? old = reactions.of(participantId);
  final Map<String, int> counts = <String, int>{...?old?.counts};
  final String? previous = old?.mine;
  if (previous != null) {
    final int left = (counts[previous] ?? 0) - 1;
    if (left > 0) {
      counts[previous] = left;
    } else {
      counts.remove(previous);
    }
  }
  if (kind != null) counts[kind] = (counts[kind] ?? 0) + 1;
  return PredictionReactionsDto(
    schemaVersion: reactions.schemaVersion,
    reactions: <PredictionReactionTallyDto>[
      for (final PredictionReactionTallyDto t in reactions.reactions)
        if (t.participantId != participantId) t,
      if (counts.isNotEmpty)
        PredictionReactionTallyDto(
          participantId: participantId,
          counts: counts,
          mine: kind,
        ),
    ],
  );
}
