import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'widgets/fixture_standings_board.dart';

/// The bottom-tab leaderboard surface.
///
/// It narrows the display to seasons that actually carry current-month
/// fixtures, then renders the reference-style leaderboard board.
class LeaderboardsScreen extends ConsumerWidget {
  const LeaderboardsScreen({this.userDisplayName, super.key});

  final String? userDisplayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ActiveSeasonDto>> seasons = ref.watch(
      activeSeasonsProvider,
    );
    final AsyncValue<List<CurrentMonthFixtureItemDto>> monthFixtures = ref
        .watch(currentMonthFixturesProvider);

    return Scaffold(
      backgroundColor: tokens.background,
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            l10n.leaderboardsLoadFailed,
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
        data: (items) {
          final Set<String>? seasonsWithFixtures = monthFixtures.hasValue
              ? monthFixtures.value!
                    .map((item) => item.fixture.seasonId)
                    .toSet()
              : null;

          final List<ActiveSeasonDto> visible = seasonsWithFixtures == null
              ? items
              : items
                    .where(
                      (season) => seasonsWithFixtures.contains(season.seasonId),
                    )
                    .toList(growable: false);

          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.leaderboardsJoinSeasonPrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }

          if (visible.length == 1) {
            final ActiveSeasonDto season = visible.first;
            return _SeasonLeaderboard(
              season: season,
              userDisplayName: userDisplayName,
            );
          }

          return DefaultTabController(
            length: visible.length,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                  ),
                  child: TabBar(
                    isScrollable: true,
                    tabs: visible
                        .map(
                          (season) => Tab(
                            key: Key('leaderboards.season.${season.seasonId}'),
                            text:
                                '${season.competitionName} · ${season.seasonLabel}',
                          ),
                        )
                        .toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: visible
                        .map(
                          (season) => _SeasonLeaderboard(
                            season: season,
                            userDisplayName: userDisplayName,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SeasonLeaderboard extends StatelessWidget {
  const _SeasonLeaderboard({
    required this.season,
    required this.userDisplayName,
  });

  final ActiveSeasonDto season;
  final String? userDisplayName;

  @override
  Widget build(BuildContext context) {
    return FixtureStandingsBoard(
      seasonId: season.seasonId,
      keyPrefix: 'leaderboards',
      myDisplayName: userDisplayName,
      competitionName: season.competitionName,
      seasonLabel: season.seasonLabel,
      startAt: season.startAt,
      endAt: season.endAt,
      showHeader: true,
      onBack: () => Navigator.of(context).maybePop(),
    );
  }
}
