/// The season standings board, as one widget both leaderboard surfaces show.
///
/// Before this existed the app had two leaderboards: the bottom-tab screen
/// drew its own `ListTile` rows off the fixture board, while the season screen
/// drew the podium off the season board. The podium, the movement arrows and
/// the accuracy figure therefore lived on a screen most users never opened.
/// Rather than build the same three features a second time against a second
/// DTO, both surfaces now render this.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../competition/widgets/async_list_view.dart';
import '../leaderboards_providers.dart';
import 'leaderboard_board.dart';

/// Renders `GET /seasons/{id}/leaderboard` as a [LeaderboardBoard].
///
/// [keyPrefix] is the widget-test key namespace of the surface embedding it,
/// so the two callers keep the keys their own tests already assert instead of
/// sharing one namespace and colliding when both are on screen.
class SeasonStandingsBoard extends ConsumerWidget {
  /// Creates the board for [seasonId].
  const SeasonStandingsBoard({
    required this.seasonId,
    required this.keyPrefix,
    super.key,
  });

  /// The season whose standings to show.
  final String seasonId;

  /// The key namespace for the rendered rows.
  final String keyPrefix;

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
        keyPrefix: keyPrefix,
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
              // so the arrow and the place can never come from different
              // reads.
              movement:
                  e.previousRank == null ? null : e.previousRank! - e.rank,
              // Accuracy is exact_scoreline alone, over settled fixtures. No
              // settled fixture means no accuracy -- not 0% -- so the label is
              // omitted rather than showing a zero nobody earned.
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
