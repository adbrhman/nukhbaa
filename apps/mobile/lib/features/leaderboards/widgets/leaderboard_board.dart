// ignore_for_file: sort_child_properties_last
/// The presentation for the ranked board.
///
/// The main leaderboards tab uses the reference-style mobile layout:
/// summary metrics, podium, update/gap strip, and a compact ranked table. The ranking values remain
/// server-produced; the widget only presents them and derives viewer-local
/// display values from the already-loaded board.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/user_avatar.dart';

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
    final String? standing = viewerLeads
        ? 'أنت في الصدارة 🥇'
        : gapToLeader != null && gapToLeader > 0
        ? '${_arabicPoints(gapToLeader)} للوصول للمرتبة ${entries.first.rank}'
        : null;

    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    // PERF: `ListView(children: ...)` instantiates and lays out every row up
    // front, and a monthly board is the entire user base -- every row below
    // the fold was built for nothing. The fixed header block stays eager (a
    // handful of widgets); only the ranked rows become lazy.
    //
    // Order is the reading order: where am I and how far is the top (the
    // summary), who leads (the podium), then everyone else (the table).
    final List<Widget> leading = <Widget>[
      if (showHeader)
        _SummaryCard(
          viewer: viewer,
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
      if (rest.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        const _TableHeader(),
      ],
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
          isLast: row == rest.length - 1,
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
  });

  final BoardEntry? viewer;

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

    final String semantics = item == null
        ? 'لست في هذا الترتيب بعد'
        : <String>[
            'مركزك ${item.rank}',
            _arabicPoints(item.points),
            if (accuracyPercent != null) 'الدقة $accuracyPercent%',
            if (line != null) line,
          ].join('، ');

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
                      Text('مركزك', style: labelStyle),
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
                metric('النقاط', points),
                const SizedBox(width: AppSpacing.xl),
                metric('الدقة', accuracy),
              ],
            ),
            if (line != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(height: 1, color: t.border),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StandingPill(text: line, isLead: standingIsLead),
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
    final Color wash = (isLead ? t.gold : t.primary).withValues(alpha: 0.14);
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

    // Second, first, third from left to right in either reading direction:
    // the podium is a picture, not a sentence.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 212,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : _PodiumTile(
                      entry: second,
                      keyPrefix: keyPrefix,
                      height: 144,
                      isMe: second.participantId == myParticipantId,
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PodiumTile(
                entry: first,
                keyPrefix: keyPrefix,
                height: 172,
                isMe: first.participantId == myParticipantId,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : _PodiumTile(
                      entry: third,
                      keyPrefix: keyPrefix,
                      height: 136,
                      isMe: third.participantId == myParticipantId,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumTile extends StatelessWidget {
  const _PodiumTile({
    required this.entry,
    required this.keyPrefix,
    required this.height,
    required this.isMe,
  });

  static const double _avatar = 52;

  final BoardEntry entry;
  final String keyPrefix;
  final double height;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color medal = _medal(t, entry.rank);

    // Flat tile: the medal lives in the avatar ring and the rank pill only,
    // so three tiles never turn into three differently coloured cards.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Container(
            key: Key('$keyPrefix.item.${entry.participantId}'),
            width: double.infinity,
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              _avatar / 2 + AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? Color.alphaBlend(
                      t.primary.withValues(alpha: 0.12),
                      t.surface,
                    )
                  : t.surface,
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: isMe ? t.primaryText : t.border,
                width: isMe ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _RankPill(rank: entry.rank, color: medal),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  entry.displayName,
                  key: Key('$keyPrefix.participant.${entry.participantId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.labelMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.pointsLabel,
                  key: Key('$keyPrefix.points.${entry.participantId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (entry.subtitle != null)
                  Text(
                    entry.subtitle!,
                    key: Key('$keyPrefix.entries.${entry.participantId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                if (entry.outcome != null) ...<Widget>[
                  const SizedBox(height: 2),
                  _OutcomeMark(entry: entry, keyPrefix: keyPrefix),
                ],
              ],
            ),
          ),
          Positioned(
            top: -_avatar / 2,
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: <Widget>[
                UserAvatar(
                  displayName: entry.displayName,
                  avatarUrl: entry.avatarUrl,
                  size: _avatar,
                  gradient: false,
                  borderColor: medal,
                  borderWidth: 2.5,
                ),
                if (entry.rank == 1)
                  Positioned(
                    top: -14,
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: t.gold,
                      size: AppSizes.iconMd,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _medal(AppTokens t, int rank) => switch (rank) {
  1 => t.gold,
  2 => t.silver,
  3 => t.bronze,
  _ => t.primary,
};

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Text(
        '$rank',
        style: context.text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// Column widths shared by the table header and every row, so each header
// label sits over its own figures. Header and rows share one horizontal
// padding and neither carries a side border, so the columns line up exactly.
const double _rankColumnWidth = 28;
const double _accuracyColumnWidth = 42;
const double _matchesColumnWidth = 44;
const double _pointsColumnWidth = 42;
const double _movementColumnWidth = 30;
const EdgeInsets _tableCellPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: 10,
);

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    Widget cell(String name, String label, double width) => SizedBox(
      key: Key('boardHeader.$name'),
      width: width,
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
    // Mirrors _BoardRow: rank, a gap, the player (avatar and name), a 4px
    // gap, then the four fixed columns.
    return ExcludeSemantics(
      child: Container(
        padding: _tableCellPadding,
        decoration: BoxDecoration(
          color: t.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: context.text.labelSmall?.copyWith(
            color: t.textMuted,
            fontWeight: FontWeight.w700,
          ),
          child: Row(
            children: <Widget>[
              cell('rank', 'المركز', _rankColumnWidth),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('اللاعب')),
              const SizedBox(width: 4),
              cell('accuracy', 'الدقة', _accuracyColumnWidth),
              cell('matches', 'المباريات', _matchesColumnWidth),
              cell('points', 'النقاط', _pointsColumnWidth),
              cell('movement', 'الحركة', _movementColumnWidth),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.entry,
    required this.keyPrefix,
    required this.isMe,
    required this.isLast,
  });

  final BoardEntry entry;
  final String keyPrefix;
  final bool isMe;

  /// The table's last row rounds the bottom corners and drops the divider.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int? accuracyPercent = entry.accuracyPercent;
    final String accuracy = accuracyPercent == null ? '—' : '$accuracyPercent%';
    final String matches = entry.matchesCount?.toString() ?? '—';
    final Color strong = isMe ? t.primaryText : t.textPrimary;

    final TextStyle? figure = context.text.labelSmall?.copyWith(
      color: t.textMuted,
      fontWeight: FontWeight.w700,
    );

    return Semantics(
      container: true,
      label: <String>[
        'المركز ${entry.rank}',
        entry.displayName,
        _arabicPoints(entry.points),
        if (accuracyPercent != null) 'الدقة $accuracyPercent%',
        if (isMe) 'أنت',
      ].join('، '),
      excludeSemantics: true,
      child: Container(
        key: Key('$keyPrefix.item.${entry.participantId}'),
        padding: _tableCellPadding,
        decoration: BoxDecoration(
          color: isMe
              ? Color.alphaBlend(t.primary.withValues(alpha: 0.14), t.surface)
              : t.surface,
          borderRadius: isLast
              ? const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.lg),
                )
              : null,
          border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: _rankColumnWidth,
              child: Text(
                '${entry.rank}',
                textAlign: TextAlign.center,
                style: context.text.labelMedium?.copyWith(
                  color: isMe ? t.primaryText : t.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            UserAvatar(
              displayName: entry.displayName,
              avatarUrl: entry.avatarUrl,
              size: 32,
              gradient: false,
              borderColor: isMe ? t.primaryText : t.border,
              borderWidth: 1.5,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Text(
                  entry.displayName,
                  key: Key('$keyPrefix.participant.${entry.participantId}'),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: _accuracyColumnWidth,
              child: Text(
                accuracy,
                key: Key('$keyPrefix.accuracy.${entry.participantId}'),
                textAlign: TextAlign.center,
                style: figure,
              ),
            ),
            SizedBox(
              width: _matchesColumnWidth,
              child: Text(
                matches,
                key: Key('$keyPrefix.matches.${entry.participantId}'),
                textAlign: TextAlign.center,
                style: figure,
              ),
            ),
            SizedBox(
              width: _pointsColumnWidth,
              child: Text(
                entry.points.toString(),
                key: Key('$keyPrefix.points.${entry.participantId}'),
                textAlign: TextAlign.center,
                style: context.text.titleSmall?.copyWith(
                  color: strong,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              width: _movementColumnWidth,
              child: entry.outcome != null
                  ? _OutcomeMark(entry: entry, keyPrefix: keyPrefix)
                  : _MovementChip(
                      movement: entry.movement,
                      keyPrefix: keyPrefix,
                      participantId: entry.participantId,
                    ),
            ),
          ],
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
    final Color color = up ? t.success : t.error;
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

/// Arabic number agreement for a points figure: one, two, few (3-10) and
/// many (11+) are different words, not a plural suffix.
String _arabicPoints(int count) {
  final int tail = count % 100;
  if (count == 1) return 'نقطة واحدة';
  if (count == 2) return 'نقطتان';
  if (tail >= 3 && tail <= 10) return '$count نقاط';
  return '$count نقطة';
}
