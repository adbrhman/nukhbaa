// ignore_for_file: sort_child_properties_last
/// The presentation for the ranked board.
///
/// The main leaderboards tab uses the reference-style mobile layout:
/// summary metrics, a podium of floating pictures (the leader raised and
/// crowned, each place on a diamond), then every other line as a card of
/// its own. The ranking values remain
/// server-produced; the widget only presents them and derives viewer-local
/// display values from the already-loaded board.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/user_avatar.dart';
import '../../../l10n/app_localizations.dart';
import 'champion_crown.dart';
import 'duel_wins_mark.dart';

class BoardEntry {
  const BoardEntry({
    required this.participantId,
    required this.rank,
    required this.displayName,
    required this.points,
    required this.pointsLabel,
    this.subtitle,
    this.matchesCount,
    this.movement,
    this.accuracyPercent,
    this.avatarUrl,
    this.outcome,
    this.outcomeLabel,
    this.champion = false,
    this.duelWins = 0,
  });

  final String participantId;
  final int rank;
  final String displayName;
  final int points;
  final String pointsLabel;
  final String? subtitle;

  /// The counted-matches figure for the table's matches column. Carried as
  /// a number beside [subtitle]: the column used to pull the first digit
  /// out of the localized subtitle, and the Arabic forms for zero, one
  /// and two carry no digit at all, so those rows printed a dash.
  final int? matchesCount;
  final int? movement;

  /// Exact scorelines over decided fixtures, as a whole percentage; null
  /// before anything is decided. The board prints the bare figure: the
  /// column header and the summary label already say what it measures.
  final int? accuracyPercent;
  final String? avatarUrl;

  /// Where the week would leave this line if it closed now, as the server
  /// projected it (weekly league only). Null on every other board, which
  /// keeps its movement arrows.
  final BoardOutcome? outcome;

  /// The words for [outcome], read out by the mark's tooltip.
  final String? outcomeLabel;

  /// Whether this player was crowned champion of a month: a crown beside
  /// the name. Only the boards keyed by user can tell (the season and the
  /// weekly league); a monthly board's lines carry no user id.
  final bool champion;

  /// Duels this player won in the board's month: a mark beside the name
  /// when above zero. Only the month's board reads them.
  final int duelWins;
}

/// A weekly-league line's projected result, drawn from the server's
/// `projected_outcome`; the board never decides it.
enum BoardOutcome {
  /// Inside the promotion zone.
  promoted,

  /// Between the zones.
  held,

  /// Inside the relegation zone.
  relegated,
}

class LeaderboardBoard extends StatelessWidget {
  const LeaderboardBoard({
    required this.entries,
    required this.keyPrefix,
    this.myParticipantId,
    this.myDisplayName,
    this.showHeader = false,
    this.header,
    super.key,
  });

  final List<BoardEntry> entries;
  final String keyPrefix;
  final String? myParticipantId;
  final String? myDisplayName;

  /// Whether the viewer summary (rank / points / accuracy, with the gap to
  /// the leader inside it) leads the list. The page title, period and scope
  /// switch live above the board in the leaderboards tab, so they stay put
  /// while a board loads.
  final bool showHeader;

  /// Leads the list and scrolls with it -- the champion's hero on the
  /// month's board while a crowning is celebrated.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final BoardEntry? viewer = _findViewer();
    final List<BoardEntry> podium = entries.take(3).toList(growable: false);
    final List<BoardEntry> rest = entries.skip(3).toList(growable: false);
    // Competition ranking (1-1-1-4): everyone tied on the top total holds
    // rank 1, so a rank-1 viewer is the leader and every other viewer is
    // measured to the leader -- never to the row above, which may be a tie
    // and used to print "0 points to reach rank 1".
    final bool viewerLeads = viewer != null && viewer.rank == 1;
    final int? gapToLeader =
        viewer != null && !viewerLeads && entries.isNotEmpty
        ? entries.first.points - viewer.points
        : null;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? standing = viewerLeads
        ? l10n.boardYouLead
        : gapToLeader != null && gapToLeader > 0
        ? l10n.boardGapToRank(l10n.boardPoints(gapToLeader), entries.first.rank)
        : null;
    // The next rung above the viewer (script 125: next step): the nearest
    // higher total and the rank it holds, shown before the gap to the
    // leader when that rung is not the top, so a viewer far down the
    // board has a step within reach.
    BoardEntry? above;
    if (viewer != null && !viewerLeads) {
      for (final BoardEntry entry in entries) {
        if (entry.points > viewer.points &&
            (above == null || entry.points < above.points)) {
          above = entry;
        }
      }
    }
    final BoardEntry? step = above;
    final String? nextStep = viewer != null && step != null && step.rank > 1
        ? l10n.boardGapToRank(
            l10n.boardPoints(step.points - viewer.points),
            step.rank,
          )
        : null;

    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    // PERF: `ListView(children: ...)` instantiates and lays out every row up
    // front, and a monthly board is the entire user base -- every row below
    // the fold was built for nothing. The fixed header block stays eager (a
    // handful of widgets); only the ranked rows become lazy.
    //
    // Order is the reading order: where am I and how far is the top (the
    // summary), who leads (the podium), then everyone else (the table).
    final Widget? lead = header;
    final List<Widget> leading = <Widget>[
      if (lead != null) ...<Widget>[
        lead,
        const SizedBox(height: AppSpacing.lg),
      ],
      if (showHeader)
        _SummaryCard(
          viewer: viewer,
          nextStep: nextStep,
          standing: standing,
          standingIsLead: viewerLeads,
        ),
      if (showHeader) const SizedBox(height: AppSpacing.lg),
      if (podium.isNotEmpty)
        _Podium(
          entries: podium,
          keyPrefix: keyPrefix,
          myParticipantId: viewer?.participantId,
        ),
      if (!showHeader && standing != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _StandingPill(text: standing, isLead: viewerLeads),
        ),
      ],
      // nk-board-cards: the rest are cards of their own, no table header.
      if (rest.isNotEmpty) const SizedBox(height: AppSpacing.lg),
    ];

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        showHeader ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl + bottomInset,
      ),
      itemCount: leading.length + rest.length,
      itemBuilder: (BuildContext context, int index) {
        if (index < leading.length) return leading[index];
        final int row = index - leading.length;
        final BoardEntry entry = rest[row];
        return _BoardRow(
          entry: entry,
          keyPrefix: keyPrefix,
          isMe: entry.participantId == viewer?.participantId,
        );
      },
    );
  }

  BoardEntry? _findViewer() {
    if (myParticipantId != null) {
      for (final BoardEntry entry in entries) {
        if (entry.participantId == myParticipantId) return entry;
      }
    }
    final String name = myDisplayName?.trim() ?? '';
    if (name.isEmpty) return null;
    // Display names are not unique, and taking the first match meant a second
    // user with the same name saw a stranger's row marked as their own, with
    // the gap-to-leader strip computed from it. Ambiguity is answered with no
    // highlight at all rather than with the wrong one.
    BoardEntry? match;
    for (final BoardEntry entry in entries) {
      if (entry.displayName.trim() != name) continue;
      if (match != null) return null;
      match = entry;
    }
    return match;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.viewer,
    required this.standing,
    required this.standingIsLead,
    this.nextStep,
  });

  final BoardEntry? viewer;

  /// The gap to the next rank above, when it is not the top (script 125).
  final String? nextStep;

  /// The gap-to-leader line, or the "you lead" line; null when neither
  /// applies (no viewer on the board, or a viewer level with no one ahead).
  final String? standing;
  final bool standingIsLead;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final BoardEntry? item = viewer;
    final String rank = item?.rank.toString() ?? '—';
    final String points = item?.points.toString() ?? '—';
    final int? accuracyPercent = item?.accuracyPercent;
    final String accuracy = accuracyPercent == null ? '—' : '$accuracyPercent%';
    final String? line = standing;
    final String? next = nextStep;

    final TextStyle? labelStyle = context.text.labelSmall?.copyWith(
      color: t.textMuted,
      fontWeight: FontWeight.w600,
    );

    Widget metric(String label, String value) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: labelStyle),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.text.titleLarge?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      );
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String semantics = item == null
        ? l10n.boardNotRanked
        : <String>[
            l10n.boardYourRankIs(item.rank),
            l10n.boardPoints(item.points),
            if (accuracyPercent != null) l10n.boardAccuracyIs(accuracyPercent),
            ?next,
            ?line,
          ].join(l10n.boardListSeparator);

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.boardYourRank, style: labelStyle),
                      Text(
                        rank,
                        style: context.text.displaySmall?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                metric(l10n.boardColPoints, points),
                const SizedBox(width: AppSpacing.xl),
                metric(l10n.boardColAccuracy, accuracy),
              ],
            ),
            if (line != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(height: 1, color: t.border),
              const SizedBox(height: AppSpacing.md),
              // script 125: the next rung first, then the top.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  if (next != null) _StandingPill(text: next, isLead: false),
                  _StandingPill(text: line, isLead: standingIsLead),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one line that says how far the viewer is from the top: blue while
/// chasing, gold once leading. Gold is kept for achievement only.
class _StandingPill extends StatelessWidget {
  const _StandingPill({required this.text, required this.isLead});

  final String text;
  final bool isLead;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color fg = isLead ? t.gold : t.primaryText;
    // The lead sits on amber: a gold wash read grey on the navy (CA-19).
    final Color wash = isLead
        ? t.goldContainer
        : t.primary.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.entries,
    required this.keyPrefix,
    required this.myParticipantId,
  });

  final List<BoardEntry> entries;
  final String keyPrefix;
  final String? myParticipantId;

  @override
  Widget build(BuildContext context) {
    final BoardEntry first = entries[0];
    final BoardEntry? second = entries.length > 1 ? entries[1] : null;
    final BoardEntry? third = entries.length > 2 ? entries[2] : null;
    final List<BoardEntry?> steps = <BoardEntry?>[first, second, third];

    Widget place(BoardEntry? entry, int position) => Expanded(
      child: entry == null
          ? const SizedBox.shrink()
          : _PodiumTile(
              entry: entry,
              keyPrefix: keyPrefix,
              step: _podiumStep(steps, position),
              isMe: entry.participantId == myParticipantId,
            ),
    );

    // Second, first, third from left to right in either reading direction:
    // the podium is a picture, not a sentence.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          place(second, 1),
          const SizedBox(width: AppSpacing.sm),
          place(first, 0),
          const SizedBox(width: AppSpacing.sm),
          place(third, 2),
        ],
      ),
    );
  }
}

/// One place on the podium: the picture in its medal ring with the place on
/// a diamond below it, the name, the points. No card: the pictures float,
/// and the leader's step stands taller and wears the crown.
class _PodiumTile extends StatelessWidget {
  const _PodiumTile({
    required this.entry,
    required this.keyPrefix,
    required this.step,
    required this.isMe,
  });

  final BoardEntry entry;
  final String keyPrefix;

  /// The step this place stands on, 0 the highest (see [_podiumStep]).
  final int step;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color medal = _medal(t, entry.rank);
    final double avatar = _stepAvatars[step];
    final bool top = step == 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: Key('$keyPrefix.item.${entry.participantId}'),
        width: double.infinity,
        padding: EdgeInsets.only(bottom: _stepLifts[step]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (entry.rank == 1)
              Icon(
                Icons.workspace_premium_rounded,
                color: t.goldAccent,
                size: top ? AppSizes.iconLg + 4 : AppSizes.iconMd,
              ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: _diamond / 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: top
                          ? <BoxShadow>[
                              BoxShadow(
                                color: medal.withValues(alpha: 0.35),
                                blurRadius: 18,
                              ),
                            ]
                          : null,
                    ),
                    child: UserAvatar(
                      displayName: entry.displayName,
                      avatarUrl: entry.avatarUrl,
                      size: avatar,
                      gradient: false,
                      borderColor: isMe ? t.primaryText : medal,
                      borderWidth: 3,
                    ),
                  ),
                ),
                _RankDiamond(rank: entry.rank, color: medal),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    entry.displayName,
                    key: Key('$keyPrefix.participant.${entry.participantId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.text.labelLarge?.copyWith(
                      color: isMe ? t.primaryText : t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (entry.champion) ...<Widget>[
                  const SizedBox(width: 3),
                  ChampionCrown(
                    key: Key('$keyPrefix.crown.${entry.participantId}'),
                    size: 14,
                    semanticLabel: AppLocalizations.of(
                      context,
                    ).championCrownLabel,
                  ),
                ],
                if (entry.duelWins > 0) ...<Widget>[
                  const SizedBox(width: 4),
                  DuelWinsMark(
                    key: Key('$keyPrefix.duelWins.${entry.participantId}'),
                    wins: entry.duelWins,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.stars_rounded,
                  size: AppSizes.iconXs,
                  color: t.primaryText,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    entry.pointsLabel,
                    key: Key('$keyPrefix.points.${entry.participantId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (entry.subtitle != null)
              Text(
                entry.subtitle!,
                key: Key('$keyPrefix.entries.${entry.participantId}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: t.textMuted),
              ),
            if (entry.outcome != null) ...<Widget>[
              const SizedBox(height: 2),
              _OutcomeMark(entry: entry, keyPrefix: keyPrefix),
            ],
          ],
        ),
      ),
    );
  }
}

/// The podium steps, first to third: the picture's size and the room left
/// under the tile, so the leader stands raised.
const List<double> _stepAvatars = <double>[76, 62, 62];
const List<double> _stepLifts = <double>[28, 10, 0];

/// The diamond the place is written on.
const double _diamond = 26;

/// The step for the place at [position] (0 first, 2 third). Players tied
/// on a rank stand together at the lowest step they share: three tied on 1
/// stood at three heights as if first, second and third (UI-12).
int _podiumStep(List<BoardEntry?> steps, int position) {
  final int rank = steps[position]!.rank;
  int lowest = position;
  for (int i = position + 1; i < steps.length; i++) {
    if (steps[i]?.rank == rank) lowest = i;
  }
  return lowest;
}

Color _medal(AppTokens t, int rank) => switch (rank) {
  1 => t.goldAccent,
  2 => t.silver,
  3 => t.bronze,
  _ => t.primary,
};

/// The place on a diamond: a dark face with the medal's rim, the figure in
/// text colour on it. The medal is the rim and the ring; silver and bronze
/// as text fell under 4.5:1 (UI-13).
class _RankDiamond extends StatelessWidget {
  const _RankDiamond({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: _diamond,
        height: _diamond,
        decoration: BoxDecoration(
          color: t.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$rank',
              style: context.text.labelMedium?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line below the podium, as a card of its own: the place, the picture,
/// the name over the accuracy and the counted matches, then the move and
/// the points.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.entry,
    required this.keyPrefix,
    required this.isMe,
  });

  final BoardEntry entry;
  final String keyPrefix;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final int? accuracyPercent = entry.accuracyPercent;
    final String accuracy = accuracyPercent == null ? '—' : '$accuracyPercent%';
    final String matches =
        entry.subtitle ?? entry.matchesCount?.toString() ?? '—';
    final TextStyle? detail = context.text.labelSmall?.copyWith(
      color: t.textSecondary,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        container: true,
        label: <String>[
          l10n.boardRankIs(entry.rank),
          entry.displayName,
          l10n.boardPoints(entry.points),
          if (accuracyPercent != null) l10n.boardAccuracyIs(accuracyPercent),
          if (entry.champion) l10n.championCrownLabel,
          if (entry.duelWins > 0) duelWinsLabel(entry.duelWins),
          if (isMe) l10n.boardYou,
        ].join(l10n.boardListSeparator),
        excludeSemantics: true,
        child: Container(
          key: Key('$keyPrefix.item.${entry.participantId}'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? Color.alphaBlend(t.primary.withValues(alpha: 0.14), t.surface)
                : t.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(
              color: isMe ? t.primaryText : t.border,
              width: isMe ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 30,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${entry.rank}',
                    key: Key('$keyPrefix.rank.${entry.participantId}'),
                    textAlign: TextAlign.center,
                    style: context.text.titleSmall?.copyWith(
                      color: isMe ? t.primaryText : t.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              UserAvatar(
                displayName: entry.displayName,
                avatarUrl: entry.avatarUrl,
                size: 40,
                gradient: false,
                borderColor: isMe ? t.primaryText : t.border,
                borderWidth: 1.5,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            entry.displayName,
                            key: Key(
                              '$keyPrefix.participant.${entry.participantId}',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(
                              color: isMe ? t.primaryText : t.textPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (entry.champion) ...<Widget>[
                          const SizedBox(width: 4),
                          ChampionCrown(
                            key: Key('$keyPrefix.crown.${entry.participantId}'),
                            size: 16,
                          ),
                        ],
                        if (entry.duelWins > 0) ...<Widget>[
                          const SizedBox(width: 6),
                          DuelWinsMark(
                            key: Key(
                              '$keyPrefix.duelWins.${entry.participantId}',
                            ),
                            wins: entry.duelWins,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // The secondary figures, small, under the name.
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(l10n.boardColAccuracy, style: detail),
                        Text(
                          accuracy,
                          key: Key(
                            '$keyPrefix.accuracy.${entry.participantId}',
                          ),
                          style: detail,
                        ),
                        Text('·', style: detail),
                        Text(
                          matches,
                          key: Key('$keyPrefix.matches.${entry.participantId}'),
                          style: detail,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 30,
                child: entry.outcome != null
                    ? _OutcomeMark(entry: entry, keyPrefix: keyPrefix)
                    : _MovementChip(
                        movement: entry.movement,
                        keyPrefix: keyPrefix,
                        participantId: entry.participantId,
                      ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.stars_rounded,
                size: AppSizes.iconXs,
                color: t.primaryText,
              ),
              const SizedBox(width: 3),
              Text(
                entry.points.toString(),
                key: Key('$keyPrefix.points.${entry.participantId}'),
                style: context.text.titleMedium?.copyWith(
                  color: isMe ? t.primaryText : t.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementChip extends StatelessWidget {
  const _MovementChip({
    required this.movement,
    required this.keyPrefix,
    required this.participantId,
  });

  final int? movement;
  final String keyPrefix;
  final String participantId;

  @override
  Widget build(BuildContext context) {
    final int? m = movement;
    final AppTokens t = context.tokens;
    // No move, or no earlier snapshot: the same muted dash the weekly league
    // draws for "held", so the column never reads as an empty cell.
    if (m == null || m == 0) {
      return Center(
        child: Icon(
          Icons.remove_rounded,
          key: Key('$keyPrefix.movement.$participantId.none'),
          size: 16,
          color: t.textMuted,
        ),
      );
    }
    final bool up = m > 0;
    // The text shades: success/error read 3.7:1 / 4.2:1 on the blue viewer
    // row (UI-13).
    final Color color = up ? t.successText : t.errorText;
    // A two-digit move (or larger system text) overflowed the 30px column;
    // the chip now scales down to fit it instead.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        key: Key('$keyPrefix.movement.$participantId'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: color,
          ),
          Text(
            '${m.abs()}',
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The weekly-league mark in the movement column: an up arrow inside the
/// promotion zone, a down arrow inside the relegation zone, a dash between.
class _OutcomeMark extends StatelessWidget {
  const _OutcomeMark({required this.entry, required this.keyPrefix});

  final BoardEntry entry;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final (IconData icon, Color color) = switch (entry.outcome) {
      BoardOutcome.promoted => (Icons.arrow_upward_rounded, t.success),
      BoardOutcome.relegated => (Icons.arrow_downward_rounded, t.error),
      _ => (Icons.remove_rounded, t.textMuted),
    };
    final Widget mark = Icon(
      icon,
      key: Key(
        '$keyPrefix.outcome.${entry.participantId}.${entry.outcome?.name}',
      ),
      size: 16,
      color: color,
    );
    final String? label = entry.outcomeLabel;
    return Center(
      child: label == null ? mark : Tooltip(message: label, child: mark),
    );
  }
}
