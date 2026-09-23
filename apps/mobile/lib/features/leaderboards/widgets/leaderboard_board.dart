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
    this.accuracyLabel,
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
  final String? accuracyLabel;
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

  /// Whether the viewer summary (rank / points / accuracy) and the gap strip
  /// lead the list. The page title, period and scope switch live above the
  /// board in the leaderboards tab, so they stay put while a board loads.
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
    final bool showGap = gapToLeader != null && gapToLeader > 0;

    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    // PERF: `ListView(children: ...)` instantiates and lays out every row up
    // front, and a monthly board is the entire user base -- every row below
    // the fold was built for nothing. The fixed header block stays eager (a
    // handful of widgets); only the ranked rows become lazy.
    final List<Widget> leading = <Widget>[
      if (showHeader) _SummaryCard(viewer: viewer),
      if (showHeader) const SizedBox(height: AppSpacing.sm),
      if (podium.isNotEmpty)
        _Podium(
          entries: podium,
          keyPrefix: keyPrefix,
          myParticipantId: viewer?.participantId,
        ),
      if (viewerLeads || showGap) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _BoardMetaStrip(
          gapPoints: showGap ? gapToLeader : null,
          targetRank: entries.first.rank,
          isLeader: viewerLeads,
        ),
      ] else if (showHeader && entries.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        const _BoardMetaStrip(),
      ],
      if (rest.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _TableHeader(),
        const SizedBox(height: 4),
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
        final BoardEntry entry = rest[index - leading.length];
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
  const _SummaryCard({required this.viewer});

  final BoardEntry? viewer;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final BoardEntry? item = viewer;
    final String rank = item?.rank.toString() ?? '—';
    final String points = item?.points.toString() ?? '—';
    final String accuracy = item?.accuracyLabel ?? '—';

    Widget metric(String label, String value, IconData icon) {
      return Expanded(
        child: Column(
          children: <Widget>[
            Icon(icon, size: 17, color: t.textMuted),
            const SizedBox(height: 2),
            Text(
              value,
              style: context.text.titleMedium?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: context.text.labelSmall?.copyWith(color: t.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          metric('المركز', rank, Icons.person_outline_rounded),
          Container(width: 1, height: 40, color: t.border),
          metric('النقاط', points, Icons.star_outline_rounded),
          Container(width: 1, height: 40, color: t.border),
          metric('الدقة', accuracy, Icons.track_changes_rounded),
        ],
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

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 216,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : _PodiumTile(
                      entry: second,
                      keyPrefix: keyPrefix,
                      height: 136,
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
                      height: 126,
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

  final BoardEntry entry;
  final String keyPrefix;
  final double height;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color medal = _medal(t, entry.rank);

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
              26,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: medal.withValues(alpha: isMe ? 1.0 : 0.58),
                width: isMe ? 1.6 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[medal.withValues(alpha: 0.10), t.surface],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: medal.withValues(alpha: 0.18),
                  blurRadius: 20,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _RankPill(rank: entry.rank, color: medal),
                const SizedBox(height: 5),
                Text(
                  entry.displayName,
                  key: Key('$keyPrefix.participant.${entry.participantId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.text.labelMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.pointsLabel,
                  key: Key('$keyPrefix.points.${entry.participantId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: medal,
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
            top: 0,
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: <Widget>[
                UserAvatar(
                  displayName: entry.displayName,
                  avatarUrl: entry.avatarUrl,
                  size: 56,
                  gradient: false,
                  borderColor: medal,
                  borderWidth: 2.5,
                ),
                if (entry.rank == 1)
                  Positioned(
                    top: -12,
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: t.gold,
                      size: 22,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: color.withValues(alpha: 0.72)),
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

class _BoardMetaStrip extends StatelessWidget {
  const _BoardMetaStrip({
    this.gapPoints,
    this.targetRank,
    this.isLeader = false,
  });

  final int? gapPoints;
  final int? targetRank;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'آخر تحديث: الآن',
            style: context.text.labelSmall?.copyWith(color: t.textMuted),
          ),
        ),
        if (isLeader || (gapPoints != null && targetRank != null))
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border.all(color: t.primary.withValues(alpha: 0.45)),
            ),
            child: Text(
              isLeader
                  ? 'أنت في الصدارة 🥇'
                  : '${_arabicPoints(gapPoints!)} للوصول للمرتبة $targetRank',
              style: context.text.labelSmall?.copyWith(
                color: t.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 7,
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 28,
            child: Text('المركز', textAlign: TextAlign.center),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Text('اللاعب')),
          const SizedBox(
            width: 48,
            child: Text('الدقة', textAlign: TextAlign.center),
          ),
          const SizedBox(
            width: 52,
            child: Text('المباريات', textAlign: TextAlign.center),
          ),
          const SizedBox(
            width: 48,
            child: Text('النقاط', textAlign: TextAlign.center),
          ),
          const SizedBox(
            width: 40,
            child: Text('الحركة', textAlign: TextAlign.center),
          ),
        ],
      ),
      decoration: BoxDecoration(
        color: t.surfaceElevated.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }
}

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
    final AppTokens t = context.tokens;
    final Color accent = isMe ? t.primary : t.border;
    final String accuracy = entry.accuracyLabel ?? '—';
    final String matches = entry.matchesCount?.toString() ?? '—';

    return Container(
      key: Key('$keyPrefix.item.${entry.participantId}'),
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: isMe ? t.surfaceElevated : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent, width: isMe ? 1.4 : 1),
        boxShadow: isMe
            ? <BoxShadow>[
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.20),
                  blurRadius: 16,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(
                color: isMe ? t.primary : t.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          UserAvatar(
            displayName: entry.displayName,
            avatarUrl: entry.avatarUrl,
            size: 34,
            gradient: false,
            borderColor: isMe ? t.primary : t.border,
            borderWidth: 1.8,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Text(
                entry.displayName,
                key: Key('$keyPrefix.participant.${entry.participantId}'),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.right,
                style: context.text.bodySmall?.copyWith(
                  color: t.textPrimary,
                  fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 42,
            child: Text(
              accuracy,
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(
                color: t.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              matches,
              key: Key('$keyPrefix.matches.${entry.participantId}'),
              textAlign: TextAlign.center,
              style: context.text.labelSmall?.copyWith(
                color: t.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              entry.points.toString(),
              key: Key('$keyPrefix.points.${entry.participantId}'),
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(
                color: isMe ? t.primary : t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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
        ],
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
    if (m == null || m == 0) return const SizedBox.shrink();
    final AppTokens t = context.tokens;
    final bool up = m > 0;
    final Color color = up ? t.success : t.error;
    return Row(
      key: Key('$keyPrefix.movement.$participantId'),
      mainAxisAlignment: MainAxisAlignment.center,
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
