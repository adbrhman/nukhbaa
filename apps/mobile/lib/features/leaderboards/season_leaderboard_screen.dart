library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';
import 'widgets/leaderboard_board.dart';

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
      listBuilder: (context, entries) => LeaderboardBoard(
        keyPrefix: 'leaderboard',
        // Highlighting the viewer's own row needs the board itself to say
        // which entry is theirs (an is_me / participant_id field on the DTO).
        // Deriving it from a side read here meant this screen firing an extra
        // request just to decorate a row -- and, in the leaderboard tests,
        // consuming the scripted failure meant for the board's own read.
        myParticipantId: null,
        entries: <BoardEntry>[
          for (final LeaderboardEntryDto e in entries)
            BoardEntry(
              participantId: e.participantId,
              rank: e.rank,
              displayName: e.displayName,
              points: e.totalPoints,
              pointsLabel: l10n.pointsAbbreviated(e.totalPoints),
              subtitle: l10n.leaderboardEntriesCounted(e.entryCount),
              // previousRank is null until the season's first daily snapshot
              // exists; the subtraction is the one place movement is derived,
              // so the arrow and the place can never come from different reads.
              movement: e.previousRank == null
                  ? null
                  : e.previousRank! - e.rank,
              // Accuracy is exact_scoreline alone, over settled fixtures. No
              // settled fixture means no accuracy -- not 0% -- so the label
              // is omitted rather than showing a zero nobody earned.
              accuracyLabel: e.settledCount <= 0
                  ? null
                  : l10n.leaderboardAccuracy(
                      (e.exactCount * 100 / e.settledCount).round(),
                    ),
            ),
        ],
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
      listBuilder: (context, entries) => LeaderboardBoard(
        keyPrefix: 'leaderboard.fixture',
        // Highlighting the viewer's own row needs the board itself to say
        // which entry is theirs (an is_me / participant_id field on the DTO).
        // Deriving it from a side read here meant this screen firing an extra
        // request just to decorate a row -- and, in the leaderboard tests,
        // consuming the scripted failure meant for the board's own read.
        myParticipantId: null,
        entries: <BoardEntry>[
          for (final FixtureLeaderboardEntryDto e in entries)
            BoardEntry(
              participantId: e.participantId,
              rank: e.rank,
              displayName: e.displayName,
              points: e.totalPoints,
              pointsLabel: l10n.pointsAbbreviated(e.totalPoints),
            ),
        ],
      ),
    );
  }
}
