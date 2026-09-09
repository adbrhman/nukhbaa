/// مواسمي — أشهر كل موسم رياضي مجموعةً في سطر واحد.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/month_label.dart';
import '../competition/widgets/async_list_view.dart';
import 'season_record_providers.dart';

/// One sporting season's roll-up: its months' points added together.
class SportingSeasonTotal {
  /// Creates a roll-up.
  const SportingSeasonTotal({
    required this.cycleLabel,
    required this.totalPoints,
    required this.monthCount,
    required this.bestRank,
  });

  /// The sporting season, e.g. `2026/27`.
  final String cycleLabel;

  /// Points across every month of it.
  final int totalPoints;

  /// How many of its months the user actually played.
  final int monthCount;

  /// The best finish in any of those months.
  final int bestRank;
}

/// Groups month records into sporting seasons, newest first.
///
/// A month with no record is simply absent: the roll-up counts what the
/// user played, not what the calendar contains.
List<SportingSeasonTotal> rollUpSeasons(List<MySeasonRecordDto> records) {
  final Map<String, List<MySeasonRecordDto>> byCycle =
      <String, List<MySeasonRecordDto>>{};
  for (final MySeasonRecordDto r in records) {
    final DateTime? start = DateTime.tryParse(r.startAt);
    if (start == null) continue;
    byCycle.putIfAbsent(cycleLabelFromStart(start), () => []).add(r);
  }

  final List<SportingSeasonTotal> totals =
      <SportingSeasonTotal>[
        for (final MapEntry<String, List<MySeasonRecordDto>> e
            in byCycle.entries)
          SportingSeasonTotal(
            cycleLabel: e.key,
            totalPoints: e.value.fold<int>(0, (int s, r) => s + r.totalPoints),
            monthCount: e.value.length,
            bestRank: e.value
                .map((MySeasonRecordDto r) => r.rank)
                .reduce((int a, int b) => a < b ? a : b),
          ),
      ]..sort(
        (SportingSeasonTotal a, SportingSeasonTotal b) =>
            b.cycleLabel.compareTo(a.cycleLabel),
      );
  return totals;
}

/// شاشة "مواسمي": مجموع نقاط كل موسم رياضي عبر أشهره.
///
/// تقرأ سجلات الأشهر نفسها التي يعرضها سجل البطولات، وتجمعها حسب الموسم
/// الرياضي المشتقّ من تاريخ بداية كل شهر — فلا تحتاج مسارًا جديدًا في
/// الخادم ولا حقلًا إضافيًا في الحمولة.
class MySeasonsScreen extends ConsumerWidget {
  /// Creates the screen.
  const MySeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mySeasonsLabel, key: const Key('mySeasons.title')),
      ),
      body: AsyncListView<SportingSeasonTotal>(
        value: ref.watch(mySeasonRecordsProvider).whenData(rollUpSeasons),
        emptyMessage: l10n.mySeasonsEmpty,
        onRetry: () => ref.invalidate(mySeasonRecordsProvider),
        itemBuilder: (context, total) => _SeasonTotalRow(total: total),
      ),
    );
  }
}

class _SeasonTotalRow extends StatelessWidget {
  const _SeasonTotalRow({required this.total});

  final SportingSeasonTotal total;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color accent = switch (total.bestRank) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.textMuted,
    };

    return Container(
      key: Key('mySeasons.item.${total.cycleLabel}'),
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
              '#${total.bestRank}',
              style: context.text.labelMedium?.copyWith(color: accent),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  total.cycleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.mySeasonsMonthCount(total.monthCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.pointsAbbreviated(total.totalPoints),
            style: context.text.titleMedium?.copyWith(
              color: total.bestRank == 1 ? t.gold : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
