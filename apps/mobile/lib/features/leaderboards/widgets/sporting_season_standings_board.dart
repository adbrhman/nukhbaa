/// The sporting-season board: the monthly standings from September to August
/// summed per user by the server (`GET /leaderboard/season`). The user on
/// top when August closes is the season champion.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../competition/widgets/async_list_view.dart';
import '../leaderboards_providers.dart';
import 'leaderboard_board.dart';

/// Renders [sportingSeasonLeaderboardProvider] as a [LeaderboardBoard].
///
/// The board is keyed by user, not by participant (a participant belongs to
/// one month), so the viewer's row is found by [myUserId].
class SportingSeasonStandingsBoard extends ConsumerWidget {
  /// Creates the season board.
  const SportingSeasonStandingsBoard({
    required this.keyPrefix,
    this.myUserId,
    this.myDisplayName,
    this.showHeader = false,
    super.key,
  });

  /// The key namespace for the rendered rows.
  final String keyPrefix;

  /// The signed-in user's id.
  final String? myUserId;

  /// Fallback for finding the viewer's row.
  final String? myDisplayName;

  /// Whether the viewer summary leads the list.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SportingSeasonLeaderboardDto> standings = ref.watch(
      sportingSeasonLeaderboardProvider,
    );
    return AsyncListView<SportingSeasonEntryDto>(
      value: standings.whenData((board) => board.entries),
      emptyMessage: l10n.leaderboardSeasonEmpty,
      onRetry: () => ref.invalidate(sportingSeasonLeaderboardProvider),
      listBuilder: (context, entries) => LeaderboardBoard(
        keyPrefix: keyPrefix,
        myParticipantId: myUserId,
        myDisplayName: myDisplayName,
        showHeader: showHeader,
        entries: <BoardEntry>[
          for (final SportingSeasonEntryDto e in entries)
            BoardEntry(
              participantId: e.userId,
              rank: e.rank,
              displayName: e.displayName,
              points: e.totalPoints,
              pointsLabel: l10n.pointsAbbreviated(e.totalPoints),
              subtitle: l10n.leaderboardEntriesCounted(e.fixturesScored),
              matchesCount: e.fixturesScored,
              // Same rule as the monthly board: exact_scoreline over decided
              // fixtures, and no label at all before anything is decided.
              accuracyLabel: e.decidedCount <= 0
                  ? null
                  : l10n.leaderboardAccuracy(
                      (e.exactCount * 100 / e.decidedCount).round(),
                    ),
            ),
        ],
      ),
    );
  }
}
