/// The live fixture standings board -- the one users actually see.
///
/// ## Why this board and not the season board
/// The platform has two point stores. `scoring.fixture_scores` fills the
/// instant a result is recorded and holds every point the app has ever
/// awarded. `ledger.point_entries` was meant to be the ratified record, but
/// it is keyed on `round_id`, and this project moved to season-linked
/// fixtures (migration 0019) and left rounds behind: `round_fixtures` is
/// empty, so not one scored fixture can be posted there. The ledger is not
/// behind -- it is unreachable from the data model in use.
///
/// So the fixture board is the real board: append-only, always current, and
/// the source of every number on screen today. This widget is what both
/// leaderboard surfaces render.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../competition/widgets/async_list_view.dart';
import '../../history/prediction_history_providers.dart';
import '../leaderboards_providers.dart';
import 'leaderboard_board.dart';

/// Renders `GET /seasons/{id}/fixture-leaderboard` as a [LeaderboardBoard].
///
/// [keyPrefix] is the widget-test key namespace of the surface embedding it,
/// so the two callers keep the keys their own tests already assert instead of
/// sharing one namespace and colliding when both are on screen.
class FixtureStandingsBoard extends ConsumerWidget {
  /// Creates the board for [seasonId].
  const FixtureStandingsBoard({
    required this.seasonId,
    required this.keyPrefix,
    this.myDisplayName,
    this.competitionName,
    this.seasonLabel,
    this.startAt,
    this.endAt,
    this.showHeader = false,
    this.onBack,
    super.key,
  });

  /// The season whose live standings to show.
  final String seasonId;

  /// The key namespace for the rendered rows.
  final String keyPrefix;

  final String? myDisplayName;
  final String? competitionName;
  final String? seasonLabel;
  final String? startAt;
  final String? endAt;
  final bool showHeader;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<FixtureLeaderboardDto> standings = ref.watch(
      fixtureLeaderboardProvider(seasonId),
    );
    // The viewer's row is found by participant id first; the display name is
    // only the fallback, since two players can share a name.
    final String? myParticipantId = _myParticipantIdIn(
      ref.watch(myFixturePredictionsProvider).value ??
          const <FixturePredictionDto>[],
      seasonId,
    );
    return AsyncListView<FixtureLeaderboardEntryDto>(
      value: standings.whenData((board) => board.entries),
      emptyMessage: l10n.fixtureLeaderboardEmpty,
      onRetry: () => ref.invalidate(fixtureLeaderboardProvider(seasonId)),
      listBuilder: (context, entries) => LeaderboardBoard(
        keyPrefix: keyPrefix,
        myParticipantId: myParticipantId,
        myDisplayName: myDisplayName,
        competitionName: competitionName,
        seasonLabel: seasonLabel,
        startAt: startAt,
        endAt: endAt,
        showHeader: showHeader,
        onRefresh: () => ref.invalidate(fixtureLeaderboardProvider(seasonId)),
        onBack: onBack,
        entries: <BoardEntry>[
          for (final FixtureLeaderboardEntryDto e in entries)
            BoardEntry(
              participantId: e.participantId,
              rank: e.rank,
              displayName: e.displayName,
              points: e.totalPoints,
              pointsLabel: l10n.pointsAbbreviated(e.totalPoints),
              subtitle: l10n.leaderboardEntriesCounted(e.fixturesScored),
              // Accuracy is exact_scoreline over DECIDED fixtures -- missed
              // and pending ones are excluded, so the figure measures
              // predictions made, not attendance. Nothing decided yet means
              // no accuracy at all, so the label is omitted rather than
              // showing a 0% nobody earned.
              accuracyLabel: e.decidedCount <= 0
                  ? null
                  : l10n.leaderboardAccuracy(
                      (e.exactCount * 100 / e.decidedCount).round(),
                    ),
              // previousRank is null until the season's first daily capture,
              // and for anyone absent from it. The subtraction is the one
              // place movement is derived, so the arrow and the place can
              // never come from different reads.
              movement: e.previousRank == null
                  ? null
                  : e.previousRank! - e.rank,
              // Server-relative and server-built: the client resolves it
              // against the API base it already holds and never guesses the
              // route. Null is the normal case (no picture uploaded), not a
              // failure.
              avatarUrl: e.avatarUrl,
            ),
        ],
      ),
    );
  }
}

/// The viewer's participant id in [seasonId], taken from their own
/// prediction there -- the same source "نقاطي" uses, so both screens pick
/// the same row. `null` until they have predicted in this season.
String? _myParticipantIdIn(
  List<FixturePredictionDto> predictions,
  String seasonId,
) {
  for (final FixturePredictionDto prediction in predictions) {
    if (prediction.seasonId == seasonId) return prediction.participantId;
  }
  return null;
}
