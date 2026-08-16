library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';

/// The season's leaderboard, in two tabs: **round points** (the standings of
/// one scored round, plus its "round king" — the round's #1) and **season
/// points** (the season's cumulative standings, unchanged in meaning from
/// before this screen grew a second tab). Both are read-only projections the
/// server has already ranked (Axiom 5) — this screen only picks which board
/// to show and decorates the top three with medal badges (🥇🥈🥉); it computes
/// no rank or point value of its own (Axiom 2).
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
                key: const Key('leaderboard.tab.round'),
                text: l10n.roundLeaderboardTab,
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
            _RoundLeaderboardTab(seasonId: seasonId),
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
      leading: _RankBadge(rank: entry.rank),
      title: Text(
        entry.participantId,
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

/// The "round points" tab — a scored round's standings
/// (`GET /rounds/{id}/leaderboard`), plus a round picker (scored rounds only:
/// a round leaderboard is meaningless before it is scored) and the #1 entry
/// highlighted as the "round king".
class _RoundLeaderboardTab extends ConsumerStatefulWidget {
  const _RoundLeaderboardTab({required this.seasonId});

  final String seasonId;

  @override
  ConsumerState<_RoundLeaderboardTab> createState() =>
      _RoundLeaderboardTabState();
}

class _RoundLeaderboardTabState extends ConsumerState<_RoundLeaderboardTab> {
  String? _roundId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<RoundDto>> rounds = ref.watch(
      seasonRoundsProvider(widget.seasonId),
    );

    return rounds.when(
      skipLoadingOnRefresh: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            ErrorPresenter.message(
              error is AppError
                  ? error
                  : const AppError.transient(
                      'client.unexpected',
                      'Something went wrong. Please try again.',
                    ),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (List<RoundDto> list) {
        final scoredRounds =
            list.where((round) => round.status == 'scored').toList()
              ..sort((a, b) => a.sequence.compareTo(b.sequence));
        if (scoredRounds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                l10n.roundLeaderboardNoScoredRounds,
                key: const Key('leaderboard.round.noScoredRounds'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final bool selectedIsValid = scoredRounds.any(
          (round) => round.id == _roundId,
        );
        final String selected = selectedIsValid
            ? _roundId!
            : scoredRounds.last.id;

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DropdownButtonFormField<String>(
                key: const Key('leaderboard.roundPicker'),
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: l10n.selectRoundLabel,
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final round in scoredRounds)
                    DropdownMenuItem<String>(
                      key: Key('leaderboard.roundPicker.${round.id}'),
                      value: round.id,
                      child: Text(l10n.roundItemTitle(round.sequence)),
                    ),
                ],
                onChanged: (String? id) {
                  if (id != null) setState(() => _roundId = id);
                },
              ),
            ),
            Expanded(child: _RoundLeaderboardBody(roundId: selected)),
          ],
        );
      },
    );
  }
}

class _RoundLeaderboardBody extends ConsumerWidget {
  const _RoundLeaderboardBody({required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<RoundLeaderboardDto> board = ref.watch(
      roundLeaderboardProvider(roundId),
    );
    return AsyncListView<RoundLeaderboardEntryDto>(
      value: board.whenData((b) => b.entries),
      emptyMessage: l10n.roundLeaderboardEmpty,
      onRetry: () => ref.invalidate(roundLeaderboardProvider(roundId)),
      itemBuilder: (context, entry) => _RoundLeaderboardRow(entry: entry),
    );
  }
}

class _RoundLeaderboardRow extends StatelessWidget {
  const _RoundLeaderboardRow({required this.entry});
  final RoundLeaderboardEntryDto entry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final bool isRoundKing = entry.rank == 1;
    return ListTile(
      key: Key('leaderboard.round.item.${entry.participantId}'),
      leading: _RankBadge(rank: entry.rank),
      title: Text(
        entry.participantId,
        key: Key('leaderboard.round.participant.${entry.participantId}'),
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: isRoundKing ? FontWeight.bold : null,
        ),
      ),
      subtitle: isRoundKing
          ? Text(
              l10n.roundKingLabel,
              key: Key('leaderboard.round.king.${entry.participantId}'),
              style: TextStyle(color: tokens.gold, fontWeight: FontWeight.bold),
            )
          : null,
      trailing: Text(
        l10n.pointsAbbreviated(entry.totalPoints),
        key: Key('leaderboard.round.points.${entry.participantId}'),
        style: TextStyle(fontWeight: FontWeight.bold, color: tokens.primary),
      ),
    );
  }
}

/// The leading rank indicator shared by both tabs: the top three ranks show a
/// medal, every other rank shows its plain number, exactly as before this
/// screen grew badges.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String? medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    if (medal != null) {
      return CircleAvatar(
        backgroundColor: tokens.gold.withValues(alpha: 0.16),
        child: Text(medal, style: const TextStyle(fontSize: 18)),
      );
    }
    return CircleAvatar(child: Text('$rank'));
  }
}
