/// The champions' record: every crowned month, newest first, with its
/// champion's picture, name, points and accuracy.
///
/// The celebration on the leaderboard lasts 48 hours; this record is where
/// the champion stays afterwards.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_error_state.dart';
import '../../core/ui/app_skeleton.dart';
import '../../l10n/app_localizations.dart';
import 'champions_providers.dart';
import 'widgets/champion_crown.dart';
import 'widgets/champion_spotlight.dart';

/// Lists [monthChampionsProvider] one card per crowned month.
class ChampionsRecordScreen extends ConsumerWidget {
  /// Creates the record.
  const ChampionsRecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<MonthChampionsDto> champions = ref.watch(
      monthChampionsProvider,
    );
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          l10n.championsRecordTitle,
          key: const Key('champions.record.title'),
        ),
      ),
      body: champions.when(
        loading: () => const AppSkeletonCardList(
          key: Key('champions.record.loading'),
          itemCount: 3,
          itemHeight: 96,
        ),
        error: (error, stackTrace) => AppErrorState(
          key: const Key('champions.record.error'),
          message: l10n.championsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(monthChampionsProvider),
        ),
        data: (list) {
          final List<List<MonthChampionDto>> months = _byMonth(list.champions);
          if (months.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.championsRecordEmpty,
                  key: const Key('champions.record.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(monthChampionsProvider);
              try {
                await ref.read(monthChampionsProvider.future);
              } on Object {
                // A failed reload shows its error through the screen itself.
              }
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: months.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) =>
                  _MonthCard(champions: months[index]),
            ),
          );
        },
      ),
    );
  }
}

/// The crowned months in the server's order (newest crowning first), each
/// with its one or two champions.
List<List<MonthChampionDto>> _byMonth(List<MonthChampionDto> champions) {
  final Map<String, List<MonthChampionDto>> months =
      <String, List<MonthChampionDto>>{};
  for (final MonthChampionDto c in champions) {
    months.putIfAbsent(c.seasonId, () => <MonthChampionDto>[]).add(c);
  }
  return months.values.toList(growable: false);
}

class _MonthCard extends ConsumerWidget {
  const _MonthCard({required this.champions});

  final List<MonthChampionDto> champions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: Key('champions.record.month.${champions.first.seasonId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const ChampionCrown(size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  championTitle(l10n, champions),
                  style: context.text.titleSmall?.copyWith(
                    color: t.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          for (final MonthChampionDto c in champions) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              key: Key('champions.record.champion.${c.seasonId}.${c.userId}'),
              children: <Widget>[
                ChampionFramedPhoto(
                  displayName: c.displayName,
                  bytes: championPhotoBytes(ref, c),
                  size: 52,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          l10n.pointsAbbreviated(c.points),
                          if (c.accuracyPercent != null)
                            l10n.boardAccuracyIs(c.accuracyPercent!),
                        ].join(' · '),
                        style: context.text.labelMedium?.copyWith(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
