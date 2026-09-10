library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../history/prediction_history_providers.dart';
import '../leaderboards/leaderboards_providers.dart';
import 'season_record_providers.dart';

/// A compact personal-points dashboard backed entirely by server-produced
/// season records and season leaderboards.
class MyPointsScreen extends ConsumerWidget {
  const MyPointsScreen({this.userDisplayName, super.key});

  /// The signed-in user's display name -- only a fallback for finding the
  /// viewer's row when none of their predictions carries the season id.
  final String? userDisplayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final records = ref.watch(mySeasonRecordsProvider);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(l10n.myPoints),
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.retry,
            onPressed: () => ref.invalidate(mySeasonRecordsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            final appError = error is AppError
                ? error
                : const AppError.transient(
                    'client.unexpected',
                    'Something went wrong. Please try again.',
                  );
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 44,
                      color: tokens.error,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      ErrorPresenter.message(appError),
                      textAlign: TextAlign.center,
                      style: context.text.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    l10n.myPointsEmpty,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) => _SeasonPointsCard(
                record: rows[index],
                userDisplayName: userDisplayName,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SeasonPointsCard extends ConsumerWidget {
  const _SeasonPointsCard({required this.record, this.userDisplayName});

  final MySeasonRecordDto record;
  final String? userDisplayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final board = ref.watch(fixtureLeaderboardProvider(record.seasonId));
    final List<FixtureLeaderboardEntryDto> entries =
        board.value?.entries ?? const <FixtureLeaderboardEntryDto>[];
    final List<FixturePredictionDto> myPredictions =
        ref.watch(myFixturePredictionsProvider).value ??
        const <FixturePredictionDto>[];

    // The same board the leaderboard tab renders, so both screens show one
    // number. The viewer is found by participant id (from their own
    // prediction in this season), never as "the only rank-1 row": a tie on
    // first place used to fall through to the season record's total, which
    // read 0 while the board showed the real total.
    final FixtureLeaderboardEntryDto? me = findMyFixtureEntry(
      entries: entries,
      myPredictions: myPredictions,
      seasonId: record.seasonId,
      displayName: userDisplayName,
    );

    final int displayPoints = me?.totalPoints ?? record.totalPoints;
    final int displayRank = me?.rank ?? record.rank;

    final int? leaderPoints = entries.isEmpty
        ? null
        : entries.first.totalPoints;
    final int? gap = leaderPoints == null
        ? null
        : (leaderPoints - displayPoints < 0 ? 0 : leaderPoints - displayPoints);

    final bool isLeader = displayRank == 1;

    // Same definition as the board: exact scorelines over decided fixtures.
    final int? accuracy = me == null
        ? record.accuracyPercent
        : (me.decidedCount <= 0
              ? null
              : (me.exactCount * 100 / me.decidedCount).round());

    final int settledMatches = me?.fixturesScored ?? record.settledCount;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tokens.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.competitionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        record.seasonLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${l10n.myPointsRank}: #$displayRank',
                    style: context.text.labelMedium?.copyWith(
                      color: tokens.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    l10n.pointsAbbreviated(displayPoints),
                    style: context.text.headlineMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  l10n.myPointsLatestScored,
                  textAlign: TextAlign.end,
                  style: context.text.labelSmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final double cell = (constraints.maxWidth - AppSpacing.sm) / 2;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: cell,
                      child: _StatTile(
                        label: l10n.myPointsPerformance,
                        value: accuracy == null ? '—' : '$accuracy%',
                        tokens: tokens,
                      ),
                    ),
                    SizedBox(
                      width: cell,
                      child: _StatTile(
                        label: l10n.myPointsLeaderGap,
                        value: gap == null
                            ? '—'
                            : isLeader
                            ? l10n.myPointsLeading
                            : l10n.pointsAbbreviated(gap),
                        tokens: tokens,
                      ),
                    ),
                    SizedBox(
                      width: cell,
                      child: _StatTile(
                        label: l10n.myPointsNeededForFirst,
                        value: gap == null
                            ? '—'
                            : isLeader
                            ? l10n.myPointsLeading
                            : l10n.pointsAbbreviated(gap),
                        tokens: tokens,
                      ),
                    ),
                    SizedBox(
                      width: cell,
                      child: _StatTile(
                        label: l10n.myPointsSettledMatches,
                        value: '$settledMatches',
                        tokens: tokens,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (leaderPoints == null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.myPointsLeaderUnavailable,
                style: context.text.labelSmall?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.tokens,
  });

  final String label;
  final String value;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The viewer's row on a fixture board: by participant id first (taken from
/// their own prediction in [seasonId]), then by display name -- the same
/// fallback the leaderboard tab uses. `null` when neither matches.
FixtureLeaderboardEntryDto? findMyFixtureEntry({
  required List<FixtureLeaderboardEntryDto> entries,
  required List<FixturePredictionDto> myPredictions,
  required String seasonId,
  String? displayName,
}) {
  for (final FixturePredictionDto prediction in myPredictions) {
    if (prediction.seasonId != seasonId) continue;
    for (final FixtureLeaderboardEntryDto entry in entries) {
      if (entry.participantId == prediction.participantId) return entry;
    }
    break;
  }
  final String name = displayName?.trim() ?? '';
  if (name.isEmpty) return null;
  for (final FixtureLeaderboardEntryDto entry in entries) {
    if (entry.displayName.trim() == name) return entry;
  }
  return null;
}
