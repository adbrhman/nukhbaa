/// The weekly-league board: the caller's own group for the Riyadh week that
/// is open now (`GET /me/weekly-league`).
///
/// Everything drawn here is the server's: the rank order, the points, the
/// tier, the two zone sizes and each member's projected outcome. The client
/// names the tier and the outcome and nothing else -- it never sorts, sums or
/// decides who moves (Axioms 2/5).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/widgets/async_list_view.dart';
import '../leaderboards_providers.dart';
import 'leaderboard_board.dart';

/// The display name of the rung [tier], 1 (lowest) to 5 (highest).
///
/// A number outside the ladder is drawn as the nearest rung rather than
/// failing the whole board.
String weeklyLeagueTierName(AppLocalizations l10n, int tier) {
  if (tier <= 1) return l10n.weeklyLeagueTierBronze;
  if (tier == 2) return l10n.weeklyLeagueTierSilver;
  if (tier == 3) return l10n.weeklyLeagueTierGold;
  if (tier == 4) return l10n.weeklyLeagueTierPlatinum;
  return l10n.weeklyLeagueTierElite;
}

/// The week as the server bounded it, `week_start` to `week_end`.
///
/// The two dates are plain `YYYY-MM-DD` days and are only formatted here,
/// never shifted into the device's zone. A date the device cannot read is
/// shown as it arrived.
String weeklyLeaguePeriodLabel(
  AppLocalizations l10n,
  MyWeeklyLeagueDto league,
  String locale,
) {
  final intl.DateFormat format = intl.DateFormat('d MMMM', locale);
  String day(String raw) {
    final DateTime? parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : format.format(parsed);
  }

  return l10n.weeklyLeaguePeriod(day(league.weekStart), day(league.weekEnd));
}

/// Maps the wire value of `projected_outcome` to the board's mark.
BoardOutcome _outcomeOf(String raw) => switch (raw) {
  'promoted' => BoardOutcome.promoted,
  'relegated' => BoardOutcome.relegated,
  _ => BoardOutcome.held,
};

/// One table line as the shared board draws it.
BoardEntry _entryOf(AppLocalizations l10n, WeeklyLeagueEntryDto e) {
  final BoardOutcome outcome = _outcomeOf(e.projectedOutcome);
  return BoardEntry(
    participantId: e.userId,
    rank: e.rank,
    displayName: e.displayName.trim().isEmpty
        ? l10n.weeklyLeagueUnnamedMember
        : e.displayName,
    points: e.points,
    pointsLabel: l10n.pointsAbbreviated(e.points),
    subtitle: l10n.leaderboardEntriesCounted(e.decidedCount),
    matchesCount: e.decidedCount,
    // Same rule as the other boards: exact scorelines over decided
    // fixtures, and no label at all before anything is decided.
    accuracyPercent: e.decidedCount <= 0
        ? null
        : (e.exactCount * 100 / e.decidedCount).round(),
    avatarUrl: e.avatarUrl,
    outcome: outcome,
    outcomeLabel: switch (outcome) {
      BoardOutcome.promoted => l10n.weeklyLeagueOutcomePromoted,
      BoardOutcome.held => l10n.weeklyLeagueOutcomeHeld,
      BoardOutcome.relegated => l10n.weeklyLeagueOutcomeRelegated,
    },
  );
}

/// Renders [myWeeklyLeagueProvider]: a tier banner above a [LeaderboardBoard]
/// of the group.
class WeeklyLeagueBoard extends ConsumerWidget {
  /// Creates the weekly-league board.
  const WeeklyLeagueBoard({
    required this.keyPrefix,
    this.myUserId,
    this.showHeader = false,
    super.key,
  });

  /// The key namespace for the rendered rows.
  final String keyPrefix;

  /// The signed-in user's id, used only when no row is marked as the
  /// caller's own.
  final String? myUserId;

  /// Whether the viewer summary leads the list.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AsyncObjectView<MyWeeklyLeagueDto>(
      value: ref.watch(myWeeklyLeagueProvider),
      onRetry: () => ref.invalidate(myWeeklyLeagueProvider),
      builder: (context, league) {
        String? me = myUserId;
        for (final WeeklyLeagueEntryDto e in league.entries) {
          if (e.isMe) me = e.userId;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: _TierBanner(league: league, keyPrefix: keyPrefix),
            ),
            if (league.overtakenBy != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.trending_down_rounded),
                    title: Text(
                      l10n.weeklyLeagueOvertakenBy(league.overtakenBy!),
                      key: Key('$keyPrefix.overtaken'),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: league.entries.isEmpty
                  ? Center(
                      child: Text(
                        l10n.weeklyLeagueEmpty,
                        key: Key('$keyPrefix.empty'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : LeaderboardBoard(
                      keyPrefix: keyPrefix,
                      myParticipantId: me,
                      showHeader: showHeader,
                      entries: <BoardEntry>[
                        for (final WeeklyLeagueEntryDto e in league.entries)
                          _entryOf(l10n, e),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The rung, the group and the two zones of the week.
class _TierBanner extends StatelessWidget {
  const _TierBanner({required this.league, required this.keyPrefix});

  final MyWeeklyLeagueDto league;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color accent = switch (league.tier) {
      <= 1 => t.bronze,
      2 => t.silver,
      3 => t.gold,
      _ => t.primary,
    };
    final TextStyle? zoneStyle = context.text.labelSmall?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: accent.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.shield_rounded, color: accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  weeklyLeagueTierName(l10n, league.tier),
                  key: Key('$keyPrefix.tier'),
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                l10n.weeklyLeagueGroup(league.groupIndex + 1),
                key: Key('$keyPrefix.group'),
                style: context.text.labelSmall?.copyWith(color: t.textMuted),
              ),
            ],
          ),
          if (league.promotionZone > 0 ||
              league.relegationZone > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                if (league.promotionZone > 0)
                  Expanded(
                    child: Text(
                      l10n.weeklyLeaguePromotionZone(league.promotionZone),
                      key: Key('$keyPrefix.zone.up'),
                      style: zoneStyle?.copyWith(color: t.success),
                    ),
                  ),
                if (league.relegationZone > 0)
                  Expanded(
                    child: Text(
                      l10n.weeklyLeagueRelegationZone(league.relegationZone),
                      key: Key('$keyPrefix.zone.down'),
                      textAlign: TextAlign.end,
                      style: zoneStyle?.copyWith(color: t.error),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
