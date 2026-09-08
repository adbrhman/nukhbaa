/// The caller's championship record: every season they have played, newest
/// first, with the place they took in it.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'season_record_providers.dart';

/// Replaces the old "my active seasons" list, which named the seasons a user
/// was in without saying how any of them went.
class SeasonRecordScreen extends ConsumerWidget {
  /// Creates the record screen.
  const SeasonRecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.seasonRecord, key: const Key('seasonRecord.title')),
      ),
      body: AsyncListView<MySeasonRecordDto>(
        value: ref.watch(mySeasonRecordsProvider),
        emptyMessage: l10n.seasonRecordEmpty,
        onRetry: () => ref.invalidate(mySeasonRecordsProvider),
        itemBuilder: (context, record) => SeasonRecordRow(record: record),
      ),
    );
  }
}

/// One season's line: the place on the leading edge, the season and its
/// accuracy in the middle, the points total trailing.
class SeasonRecordRow extends StatelessWidget {
  /// Creates a record row.
  const SeasonRecordRow({required this.record, super.key});

  /// The season being shown.
  final MySeasonRecordDto record;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? accuracy = record.accuracyPercent;
    // The medal colours are the same three the leaderboard podium uses, so a
    // second place reads as second place wherever the user sees it.
    final Color accent = switch (record.rank) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.textMuted,
    };

    return Container(
      key: Key('seasonRecord.item.${record.seasonId}'),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 1.5),
            ),
            child: Text(
              '#${record.rank}',
              style: context.text.labelMedium?.copyWith(color: accent),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.seasonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // No settled fixture means no accuracy at all, so the line
                  // falls back to the entry count rather than printing "0%",
                  // which would read as a record of failure.
                  accuracy == null
                      ? l10n.leaderboardEntriesCounted(record.entryCount)
                      : l10n.leaderboardAccuracy(accuracy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.pointsAbbreviated(record.totalPoints),
            style: context.text.titleMedium?.copyWith(
              color: record.rank == 1 ? t.gold : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
