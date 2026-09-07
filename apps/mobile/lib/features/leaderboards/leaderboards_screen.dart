import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'widgets/fixture_standings_board.dart';

/// Discovery entry point for leaderboards. It uses the caller's active seasons
/// as the server-backed scope and reuses the same season leaderboard provider
/// as the contextual board opened from a fixture.
///
/// ## One board, not one per league
/// The contest is the calendar month, not the league: the admin files
/// fixtures from several leagues into the month's competition, every user
/// predicts all of them together, and the month's highest total wins. A
/// league is only a source of fixtures, so a per-league tab is not a view
/// of anything — and in practice the account carries memberships in league
/// seasons that hold **zero** fixtures, which rendered as tabs onto empty
/// boards.
///
/// So the tabs are narrowed to the seasons that actually carry a fixture
/// this month, read off [currentMonthFixturesProvider] — the same feed the
/// matches screen already watches, so this costs no new endpoint, no new
/// provider and no server change. It is also self-maintaining: next
/// month's season appears the moment it has a fixture, and an emptied
/// season drops out on its own.
///
/// Deliberately a **view** narrowing, not a data deletion: the league
/// seasons and their memberships stay in the database untouched (project
/// owner's choice — option ب). If they are ever removed for real, this
/// filter becomes a no-op rather than a thing to undo.
///
/// If the fixtures feed has not resolved (or failed), the filter is skipped
/// entirely and every active season is shown — a leaderboard must not go
/// blank because an unrelated read is in flight.
class LeaderboardsScreen extends ConsumerWidget {
  const LeaderboardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final seasons = ref.watch(activeSeasonsProvider);
    final monthFixtures = ref.watch(currentMonthFixturesProvider);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(l10n.leaderboardsScreenTitle),
        backgroundColor: tokens.background,
      ),
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
          // A single-tab TabBar is chrome around nothing — the expected
          // steady state now that the month is the competition.
          if (visible.length == 1) {
            return _SeasonLeaderboard(seasonId: visible.first.seasonId);
          }
          return DefaultTabController(
            length: visible.length,
            child: Column(
              children: <Widget>[
                TabBar(
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
                Expanded(
                  child: TabBarView(
                    children: visible
                        .map(
                          (season) =>
                              _SeasonLeaderboard(seasonId: season.seasonId),
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

/// Was a bespoke `ListTile` list; now the shared [FixtureStandingsBoard], so
/// this surface gains the podium without gaining a second rendering to
/// maintain. It keeps reading the FIXTURE board -- the store that actually
/// holds points (see [FixtureStandingsBoard] for why the ledger cannot).
class _SeasonLeaderboard extends StatelessWidget {
  const _SeasonLeaderboard({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context) =>
      FixtureStandingsBoard(seasonId: seasonId, keyPrefix: 'leaderboards');
}
