/// "Learn from your predictions" (plan P4-5): the caller's accuracy this
/// month against everyone's, the last weeks, last week's recap and the
/// patterns the server found, all from `GET /me/insights`.
///
/// Nothing is computed here: every number and every name is the server's.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/account_menu.dart';
import '../competition/widgets/async_list_view.dart';

/// `GET /me/insights`.
final insightsProvider = FutureProvider.autoDispose<InsightsDto>((ref) async {
  final api = ref.watch(authApiProvider);
  return switch (await api.myInsights()) {
    Ok<InsightsDto>(:final value) => value,
    Err<InsightsDto>(:final error) => throw error,
  };
});

/// A percent as shown, or a dash when nothing was decided.
String percentText(int? percent) => percent == null ? '-' : '$percent%';

/// The insights page.
class InsightsScreen extends ConsumerWidget {
  /// Creates the page.
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.insightsTitle, key: const Key('insights.title')),
      ),
      body: AsyncObjectView<InsightsDto>(
        value: ref.watch(insightsProvider),
        onRetry: () => ref.invalidate(insightsProvider),
        builder: (context, insights) {
          final bool nothing =
              insights.month.decided == 0 &&
              insights.lastWeek == null &&
              insights.weeks.every((w) => w.accuracy.decided == 0);
          if (nothing) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.insightsEmpty,
                  key: const Key('insights.empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              _MonthCard(insights: insights),
              const SizedBox(height: AppSpacing.lg),
              _WeeksCard(weeks: insights.weeks),
              if (insights.lastWeek != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _RecapCard(recap: insights.lastWeek!),
              ],
              const SizedBox(height: AppSpacing.lg),
              _PatternsCard(insights: insights),
            ],
          );
        },
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.insights});

  final InsightsDto insights;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final int? community = insights.communityPercent;
    return AccountMenuCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                percentText(insights.month.percent),
                key: const Key('insights.month.percent'),
                style: context.text.headlineMedium?.copyWith(
                  color: tokens.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.insightsMonthLine(
                  insights.month.correct,
                  insights.month.decided,
                ),
                key: const Key('insights.month.line'),
              ),
              if (community != null)
                Text(
                  l10n.insightsCommunity(community),
                  key: const Key('insights.community'),
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.weeks});

  final List<WeekAccuracyDto> weeks;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return AccountMenuCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.insightsWeeksTitle),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                key: const Key('insights.weeks'),
                height: 80,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final week in weeks)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: FractionallySizedBox(
                            heightFactor: ((week.accuracy.percent ?? 0) / 100)
                                .clamp(0.04, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: week.accuracy.percent == null
                                    ? tokens.textSecondary.withValues(
                                        alpha: 0.2,
                                      )
                                    : tokens.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.recap});

  final WeekRecapDto recap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BestPredictionDto? best = recap.best;
    return AccountMenuCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.insightsLastWeek(
                  recap.accuracy.correct,
                  recap.accuracy.decided,
                  recap.points,
                ),
                key: const Key('insights.lastWeek'),
              ),
              if (best != null)
                Text(
                  l10n.insightsBestPrediction(
                    best.homeTeam,
                    best.awayTeam,
                    best.points,
                  ),
                  key: const Key('insights.best'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PatternsCard extends StatelessWidget {
  const _PatternsCard({required this.insights});

  final InsightsDto insights;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? bestLeague = insights.bestLeague;
    final String? worstLeague = insights.worstLeague;
    final int? followed = insights.followedPercent;
    final int? others = insights.othersPercent;
    return AccountMenuCard(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.insightsLongestRun(insights.longestCorrectRun),
                key: const Key('insights.run'),
              ),
              if (bestLeague != null)
                Text(
                  l10n.insightsBestLeague(bestLeague),
                  key: const Key('insights.bestLeague'),
                ),
              if (worstLeague != null)
                Text(
                  l10n.insightsWorstLeague(worstLeague),
                  key: const Key('insights.worstLeague'),
                ),
              if (followed != null && others != null)
                Text(
                  l10n.insightsFollowedBias(followed, others),
                  key: const Key('insights.bias'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
