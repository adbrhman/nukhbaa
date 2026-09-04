library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_tokens.dart';
import '../../core/ui/rank_badge.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';

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
class _SeasonLeaderboardTab extends ConsumerWidget {
  const _SeasonLeaderboardTab({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SeasonLeaderboardDto> standings = ref.watch(
      seasonLeaderboardProvider(seasonId),
    );
    return AsyncListView<LeaderboardEntryDto>(
      value: standings.whenData((board) => board.entries),
      emptyMessage: l10n.seasonLeaderboardEmpty,
      onRetry: () => ref.invalidate(seasonLeaderboardProvider(seasonId)),
      itemBuilder: (context, entry) => _SeasonLeaderboardRow(entry: entry),
    );
  }
}

class _SeasonLeaderboardRow extends StatelessWidget {
  const _SeasonLeaderboardRow({required this.entry});
  final LeaderboardEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('leaderboard.item.${entry.participantId}'),
      leading: RankBadge(rank: entry.rank),
      title: Text(
        entry.displayName,
        key: Key('leaderboard.participant.${entry.participantId}'),
        style: TextStyle(color: tokens.textPrimary),
      ),
      subtitle: Text(
        l10n.leaderboardEntriesCounted(entry.entryCount),
        key: Key('leaderboard.entries.${entry.participantId}'),
      ),
      trailing: Text(
        l10n.pointsAbbreviated(entry.totalPoints),
        key: Key('leaderboard.points.${entry.participantId}'),
        style: TextStyle(fontWeight: FontWeight.bold, color: tokens.primary),
      ),
    );
  }
}

/// The "fixture points" tab — the season's live, per-fixture standings
/// (`GET /seasons/{id}/fixture-leaderboard`, Axiom 4 Amendment). Unlike the
/// old round tab, this board has no picker and no scored-round gate: it is
/// always live, aggregating every fixture scored so far.
class _FixtureLeaderboardTab extends ConsumerWidget {
  const _FixtureLeaderboardTab({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<FixtureLeaderboardDto> standings = ref.watch(
      fixtureLeaderboardProvider(seasonId),
    );
    return AsyncListView<FixtureLeaderboardEntryDto>(
      value: standings.whenData((board) => board.entries),
      emptyMessage: l10n.fixtureLeaderboardEmpty,
      onRetry: () => ref.invalidate(fixtureLeaderboardProvider(seasonId)),
      itemBuilder: (context, entry) => _FixtureLeaderboardRow(entry: entry),
    );
  }
}

class _FixtureLeaderboardRow extends StatelessWidget {
  const _FixtureLeaderboardRow({required this.entry});
  final FixtureLeaderboardEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('leaderboard.fixture.item.${entry.participantId}'),
      leading: RankBadge(rank: entry.rank),
      title: Text(
        entry.displayName,
        key: Key('leaderboard.fixture.participant.${entry.participantId}'),
        style: TextStyle(color: tokens.textPrimary),
      ),
      trailing: Text(
        l10n.pointsAbbreviated(entry.totalPoints),
        key: Key('leaderboard.fixture.points.${entry.participantId}'),
        style: TextStyle(fontWeight: FontWeight.bold, color: tokens.primary),
      ),
    );
  }
}
