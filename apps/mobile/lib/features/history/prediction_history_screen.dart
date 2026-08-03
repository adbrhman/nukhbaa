library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../competition/widgets/async_list_view.dart';
import 'prediction_history_providers.dart';

/// The caller's own aggregated prediction history — every prediction they
/// have ever submitted, across every round and season, newest first.
///
/// Shows each historical forecast (its fixture scorelines and submission
/// time). Win/loss status is intentionally NOT shown here: that requires
/// cross-referencing each fixture's recorded result
/// (`GET /rounds/{id}/scores`) per round, which is a separate, heavier read
/// this screen does not perform — a future pass can enrich each row with it.
class PredictionHistoryScreen extends ConsumerWidget {
  const PredictionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PredictionDto>> history = ref.watch(
      myPredictionsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Predictions', key: Key('history.title')),
      ),
      body: AsyncListView<PredictionDto>(
        value: history,
        emptyMessage: 'You have not submitted any predictions yet.',
        onRetry: () => ref.invalidate(myPredictionsProvider),
        itemBuilder: (context, prediction) =>
            _PredictionCard(prediction: prediction),
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.prediction});
  final PredictionDto prediction;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Card(
      key: Key('history.item.${prediction.id}'),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              prediction.submittedAt,
              key: Key('history.submittedAt.${prediction.id}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final score in prediction.fixtureScores)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${score.fixtureId}: ${score.homeGoals} - ${score.awayGoals}',
                  key: Key('history.score.${prediction.id}.${score.fixtureId}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
