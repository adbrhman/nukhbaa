library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'widgets/fixture_standings_board.dart';
import 'widgets/season_standings_board.dart';

/// The season's leaderboard, in two tabs: **fixture points** (the season's
/// live, per-fixture standings — Axiom 4 Amendment, always up to date, never
/// gated on a round being scored) and **season points** (the season's
/// cumulative standings, unchanged in meaning from before this screen grew a
/// second tab). Both are read-only projections the server has already
/// ranked (Axiom 5) — this screen only picks which board to show and
/// decorates the top three with medal badges (🥇🥈🥉); it computes no rank or
/// point value of its own (Axiom 2).
class SeasonLeaderboardScreen extends StatelessWidget {
  const SeasonLeaderboardScreen({
    required this.seasonId,
    required this.seasonLabel,
    super.key,
  });

  final String seasonId;
  final String seasonLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.leaderboardTitle(seasonLabel),
            key: const Key('leaderboard.title'),
          ),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(
                key: const Key('leaderboard.tab.fixture'),
                text: l10n.fixtureLeaderboardTab,
              ),
              Tab(
                key: const Key('leaderboard.tab.season'),
                text: l10n.seasonLeaderboardTab,
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _FixtureLeaderboardTab(seasonId: seasonId),
            _SeasonLeaderboardTab(seasonId: seasonId),
          ],
        ),
      ),
    );
  }
}

/// The "season points" tab — the season's cumulative standings
/// (`GET /seasons/{id}/leaderboard`), decorated with medal badges for the top
/// three.
class _SeasonLeaderboardTab extends StatelessWidget {
  const _SeasonLeaderboardTab({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context) =>
      SeasonStandingsBoard(seasonId: seasonId, keyPrefix: 'leaderboard');
}

/// The "fixture points" tab — the season's live, per-fixture standings
/// (`GET /seasons/{id}/fixture-leaderboard`, Axiom 4 Amendment). Unlike the
/// old round tab, this board has no picker and no scored-round gate: it is
/// always live, aggregating every fixture scored so far.
class _FixtureLeaderboardTab extends StatelessWidget {
  const _FixtureLeaderboardTab({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context) => FixtureStandingsBoard(
    seasonId: seasonId,
    keyPrefix: 'leaderboard.fixture',
  );
}
