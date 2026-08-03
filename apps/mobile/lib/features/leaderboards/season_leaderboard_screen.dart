library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';

class SeasonLeaderboardScreen extends ConsumerWidget {
  const SeasonLeaderboardScreen({
    required this.seasonId,
    required this.seasonLabel,
    super.key,
  });
  final String seasonId;
  final String seasonLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SeasonLeaderboardDto> standings = ref.watch(
      seasonLeaderboardProvider(seasonId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.leaderboardTitle(seasonLabel),
          key: const Key('leaderboard.title'),
        ),
      ),
      body: AsyncListView<LeaderboardEntryDto>(
        value: standings.whenData((board) => board.entries),
        emptyMessage: l10n.seasonLeaderboardEmpty,
        onRetry: () => ref.invalidate(seasonLeaderboardProvider(seasonId)),
        itemBuilder: (context, entry) => _LeaderboardRow(entry: entry),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});
  final LeaderboardEntryDto entry;
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('leaderboard.item.${entry.participantId}'),
      leading: CircleAvatar(
        child: Text(
          '${entry.rank}',
          key: Key('leaderboard.rank.${entry.participantId}'),
        ),
      ),
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
