/// The Hall of Fame: where Nukhba keeps its history.
///
/// Open to every signed-in player, whether or not they ever won anything. It
/// only reads what the server already publishes at `GET /champions` and holds
/// no ranking of its own: the live tables stay on the leaderboard tab. It
/// shows the season cup, the crowned months, the record of titles, the records
/// and the legends -- all derived (see `buildHallOfFame`), none typed in.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/screen_views.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_error_state.dart';
import '../../core/ui/app_skeleton.dart';
import '../../core/ui/avatar_bytes_provider.dart';
import '../../l10n/app_localizations.dart';
import 'champions_providers.dart';
import 'cup_champions_providers.dart';
import 'hall_of_fame_model.dart';
import 'widgets/champion_spotlight.dart';
import 'widgets/trophy_cup.dart';

/// The Hall of Fame screen.
class HallOfFameScreen extends ConsumerWidget implements NamedScreen {
  /// Creates the screen. [now] is the clock the season cup reads; tests pin it.
  const HallOfFameScreen({this.now, super.key});

  /// The instant the season cup is worked out for; null reads the real clock.
  final DateTime? now;

  @override
  String get screenName => ScreenNames.champions;

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
        title: Text(l10n.hallOfFame, key: const Key('champions.record.title')),
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
        data: (MonthChampionsDto list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(monthChampionsProvider);
            ref.invalidate(cupChampionsProvider);
            try {
              await ref.read(monthChampionsProvider.future);
            } on Object {
              // A failed reload shows its error through the screen itself.
            }
          },
          child: _HallBody(
            hall: buildHallOfFame(list),
            season: SportingSeasonWindow.at(now ?? DateTime.now()),
          ),
        ),
      ),
    );
  }
}

class _HallBody extends StatelessWidget {
  const _HallBody({required this.hall, required this.season});

  final HallOfFame hall;
  final SportingSeasonWindow season;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    int rank = 1;
    final List<Widget> holderRows = <Widget>[];
    for (int i = 0; i < hall.holders.length; i++) {
      if (i > 0 && hall.holders[i].count < hall.holders[i - 1].count) {
        rank = i + 1;
      }
      holderRows
        ..add(_HolderRow(holder: hall.holders[i], rank: rank))
        ..add(const SizedBox(height: AppSpacing.sm));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        _SectionHeader(
          key: const Key('hall.section.seasons'),
          title: l10n.hallSeasonsHeading,
        ),
        _SeasonCupCard(season: season),
        if (hall.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l10n.championsRecordEmpty,
              key: const Key('champions.record.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          _SubHeader(title: l10n.hallMonthsHeading),
          for (final List<MonthChampionDto> month in hall.months) ...<Widget>[
            _MonthCard(champions: month),
            const SizedBox(height: AppSpacing.md),
          ],
          _SectionHeader(
            key: const Key('hall.section.titles'),
            title: l10n.championsRecordTitle,
          ),
          ...holderRows,
          if (hall.records.isNotEmpty) ...<Widget>[
            _SectionHeader(
              key: const Key('hall.section.records'),
              title: l10n.hallRecordsHeading,
            ),
            for (final HallRecord record in hall.records) ...<Widget>[
              _RecordCard(record: record),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
        const _CupSection(),
        _SectionHeader(
          key: const Key('hall.section.legends'),
          title: l10n.hallLegendsHeading,
        ),
        if (hall.legends.isEmpty)
          const _LegendsEmpty()
        else
          for (final HallLegend legend in hall.legends) ...<Widget>[
            _LegendCard(legend: legend),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      child: Semantics(
        header: true,
        child: Row(
          children: <Widget>[
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: t.gold,
                borderRadius: AppRadius.brXs,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: context.text.titleLarge?.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: context.text.titleMedium?.copyWith(
            color: t.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// The season cup: gold, and waiting for its champion until August closes.
class _SeasonCupCard extends StatelessWidget {
  const _SeasonCupCard({required this.season});

  final SportingSeasonWindow season;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('hall.season.cup'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: t.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          TrophyCup(light: t.goldAccent, dark: t.gold, size: 76),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.hallSeasonCupTitle(season.label),
                  style: context.text.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.hallSeasonCupWaiting,
                  style: context.text.labelLarge?.copyWith(
                    color: t.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.hallSeasonCupNote('${season.endYear}'),
                  style: context.text.bodySmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One crowned month: the silver cup, the title and each champion.
class _MonthCard extends ConsumerWidget {
  const _MonthCard({required this.champions});

  final List<MonthChampionDto> champions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    return Container(
      key: Key('champions.record.month.${champions.first.seasonId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              TrophyCup(
                light: t.silver,
                dark:
                    Color.lerp(t.silver, const Color(0xFF000000), 0.3) ??
                    t.silver,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  championTitle(l10n, champions, locale),
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
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

/// The champions of the Elite Cup, by month (migration 0190): one card per
/// path, with the picture an admin added or the champion's own picture.
/// Decoration beside the months: while the list loads, when it failed, or
/// while nobody has been crowned, it takes no room at all.
class _CupSection extends ConsumerWidget {
  const _CupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CupChampionsDto? cup = ref.watch(cupChampionsProvider).value;
    if (cup == null || cup.champions.isEmpty) {
      return const SizedBox.shrink();
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    final List<Widget> children = <Widget>[
      _SectionHeader(
        key: const Key('hall.section.cup'),
        title: l10n.hallCupHeading,
      ),
    ];
    String? month;
    for (final CupChampionDto c in cup.champions) {
      if (c.monthStart != month) {
        month = c.monthStart;
        children.add(
          _SubHeader(
            title: championMonthName(cupMonthLabel(c.monthStart), locale),
          ),
        );
      }
      children
        ..add(_CupChampionCard(champion: c))
        ..add(const SizedBox(height: AppSpacing.md));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _CupChampionCard extends ConsumerWidget {
  const _CupChampionCard({required this.champion});

  final CupChampionDto champion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CupChampionDto c = champion;
    final String? path = c.photoUrl ?? c.avatarUrl;
    final String pathName = switch (c.place) {
      1 => l10n.hallCupPath1,
      2 => l10n.hallCupPath2,
      _ => l10n.hallCupPath3,
    };
    final String how = c.how == 'walkover'
        ? l10n.hallCupWalkover
        : l10n.hallCupWonFinal;
    return Container(
      key: Key('hall.cup.champion.${c.monthStart}.${c.place}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          ChampionFramedPhoto(
            displayName: c.displayName,
            bytes: path == null
                ? null
                : ref.watch(avatarBytesProvider(path)).value,
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
                  '$pathName · $how',
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
    );
  }
}

/// One row of the record of titles: place, picture, name, count and months.
class _HolderRow extends ConsumerWidget {
  const _HolderRow({required this.holder, required this.rank});

  final HallTitleHolder holder;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    final MonthChampionDto latest = holder.latest;
    final Color medal = switch (rank) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.textSecondary,
    };
    return Container(
      key: Key('hall.holder.${holder.userId}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: rank <= 3 ? medal : t.border),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: context.text.titleMedium?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChampionFramedPhoto(
            displayName: latest.displayName,
            bytes: championPhotoBytes(ref, latest),
            size: 44,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  latest.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.hallTitlesCount(holder.count),
                  style: context.text.labelMedium?.copyWith(
                    color: t.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final MonthChampionDto title in holder.titles)
                      _MonthChip(
                        label: championMonthName(title.seasonLabel, locale),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: AppRadius.brSm,
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(color: t.textSecondary),
      ),
    );
  }
}

String _recordLabel(AppLocalizations l10n, HallRecordKind kind) =>
    switch (kind) {
      HallRecordKind.mostPoints => l10n.hallRecordMostPoints,
      HallRecordKind.mostExact => l10n.hallRecordMostExact,
      HallRecordKind.biggestMargin => l10n.hallRecordBiggestMargin,
    };

/// One record: the figure, then who set it and when.
class _RecordCard extends ConsumerWidget {
  const _RecordCard({required this.record});

  final HallRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale locale = Localizations.localeOf(context);
    final String value = switch (record.kind) {
      HallRecordKind.mostExact => l10n.hallExactResults(record.value),
      HallRecordKind.mostPoints ||
      HallRecordKind.biggestMargin => l10n.pointsAbbreviated(record.value),
    };
    return Container(
      key: Key('hall.record.${record.kind.name}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: t.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _recordLabel(l10n, record.kind),
            style: context.text.labelLarge?.copyWith(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(
              color: t.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          for (final MonthChampionDto holder in record.holders) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                ChampionFramedPhoto(
                  displayName: holder.displayName,
                  bytes: championPhotoBytes(ref, holder),
                  size: 36,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        holder.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        l10n.hallRecordSetIn(
                          championMonthName(holder.seasonLabel, locale),
                        ),
                        style: context.text.labelMedium?.copyWith(
                          color: t.textSecondary,
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

/// One legend: the player and, line by line, why they are here.
class _LegendCard extends ConsumerWidget {
  const _LegendCard({required this.legend});

  final HallLegend legend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MonthChampionDto latest = legend.holder.latest;
    final List<String> reasons = <String>[
      if (legend.byTitles) l10n.hallLegendReasonTitles(legend.holder.count),
      for (final HallRecordKind kind in legend.records)
        l10n.hallLegendReasonRecord(_recordLabel(l10n, kind)),
    ];
    return Container(
      key: Key('hall.legend.${legend.holder.userId}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: t.gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ChampionFramedPhoto(
            displayName: latest.displayName,
            bytes: championPhotoBytes(ref, latest),
            size: 56,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  latest.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final String reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.workspace_premium,
                            size: 16,
                            color: t.gold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            reason,
                            style: context.text.bodySmall?.copyWith(
                              color: t.textSecondary,
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
      ),
    );
  }
}

/// No legend yet: say so, and say how a player gets in.
class _LegendsEmpty extends StatelessWidget {
  const _LegendsEmpty();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('hall.legends.empty'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: t.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.workspace_premium, size: 28, color: t.gold),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.hallLegendsEmpty,
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.hallLegendsRules,
                  style: context.text.bodySmall?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
