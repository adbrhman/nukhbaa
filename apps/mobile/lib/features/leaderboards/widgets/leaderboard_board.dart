/// The shared presentation for a ranked board: a three-place podium above a
/// list of the remaining places.
///
/// Both leaderboard tabs render through here, so the season board and the
/// fixture board cannot drift apart visually. The widget is deliberately
/// dumb: it ranks nothing and computes no points (Axiom 2 — the server has
/// already ranked these entries). The one number it derives is the gap to
/// the place above the viewer, a subtraction between two values the server
/// sent in the same response.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/user_avatar.dart';

/// One row of a board, flattened from whichever DTO the tab reads.
class BoardEntry {
  /// Creates a board row.
  const BoardEntry({
    required this.participantId,
    required this.rank,
    required this.displayName,
    required this.points,
    required this.pointsLabel,
    this.subtitle,
    this.movement,
    this.accuracyLabel,
    this.avatarUrl,
  });

  /// Stable id — also the widget key, so tests and scroll positions survive.
  final String participantId;

  /// Server-assigned place.
  final int rank;

  /// The participant's own name.
  final String displayName;

  /// Raw score, used only for the gap arithmetic.
  final int points;

  /// The localized score string, rendered as-is.
  final String pointsLabel;

  /// Optional secondary line, e.g. how many entries were counted.
  final String? subtitle;

  /// Places climbed since the last daily snapshot: positive is up, negative is
  /// down, `0` is unchanged, `null` is "nothing to compare against" (a new
  /// participant, or a season whose first snapshot has not run). Server-sent
  /// and rendered as-is -- the widget derives nothing.
  final int? movement;

  /// The localized accuracy string, or null when the participant has no
  /// settled fixture yet and therefore no accuracy at all.
  final String? accuracyLabel;

  /// The participant's server-relative profile picture URL, or null when they
  /// have none -- in which case the row draws their initial, which is the
  /// normal case and not an error state.
  final String? avatarUrl;
}

/// Podium + list. [myParticipantId] highlights the viewer's own row.
class LeaderboardBoard extends StatelessWidget {
  /// Creates the board.
  const LeaderboardBoard({
    required this.entries,
    required this.keyPrefix,
    this.myParticipantId,
    super.key,
  });

  /// Entries in the order the server ranked them.
  final List<BoardEntry> entries;

  /// Key namespace, so the two tabs' rows never collide.
  final String keyPrefix;

  /// The viewer's participant id, when it is known.
  final String? myParticipantId;

  @override
  Widget build(BuildContext context) {
    final List<BoardEntry> podium = entries.take(3).toList();
    final List<BoardEntry> rest = entries.skip(3).toList();

    // The gap to the place directly above the viewer. Null when the viewer is
    // first, absent from the board, or not identified yet.
    final int myIndex = myParticipantId == null
        ? -1
        : entries.indexWhere((e) => e.participantId == myParticipantId);
    final int? gapToNext = myIndex > 0
        ? entries[myIndex - 1].points - entries[myIndex].points
        : null;

    // The shell draws its bottom bar OVER the body (`extendBody: true`), so
    // the last row would sit under it. Scaffold reports that bar's height as
    // the body's bottom padding, which is added here rather than hard-coded --
    // a taller bar or a device with a home indicator stays correct on its own.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl + bottomInset,
      ),
      children: <Widget>[
        if (podium.isNotEmpty)
          _Podium(
            entries: podium,
            keyPrefix: keyPrefix,
            myParticipantId: myParticipantId,
          ),
        if (gapToNext != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _GapChip(points: gapToNext, rank: entries[myIndex - 1].rank),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final BoardEntry entry in rest)
          _BoardRow(
            entry: entry,
            keyPrefix: keyPrefix,
            isMe: entry.participantId == myParticipantId,
          ),
      ],
    );
  }
}

/// The medal colour for a place, or null below third.
Color? _medal(AppTokens t, int rank) => switch (rank) {
  1 => t.gold,
  2 => t.silver,
  3 => t.bronze,
  _ => null,
};

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
    // Second on one side, first raised in the middle, third on the other —
    // a symmetric arrangement, so it reads correctly in RTL without
    // mirroring.
    final BoardEntry first = entries[0];
    final BoardEntry? second = entries.length > 1 ? entries[1] : null;
    final BoardEntry? third = entries.length > 2 ? entries[2] : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: second == null
              ? const SizedBox.shrink()
              : _PodiumTile(
                  entry: second,
                  keyPrefix: keyPrefix,
                  height: 138,
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
                  height: 122,
                  isMe: third.participantId == myParticipantId,
                ),
        ),
      ],
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

  /// The tile's MINIMUM height -- what staggers the three places. It is a
  /// floor, not a fixed size: the tile grows for a participant who has an
  /// accuracy line as well as a name, a total and a count. It used to be a
  /// fixed height, which clipped the last line the moment accuracy was added.
  final double height;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color medal = _medal(t, entry.rank) ?? t.primary;

    return Container(
      key: Key('$keyPrefix.item.${entry.participantId}'),
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: medal.withValues(alpha: isMe ? 1 : 0.45)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: medal.withValues(alpha: 0.18),
            blurRadius: 18,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          UserAvatar(
            displayName: entry.displayName,
            avatarUrl: entry.avatarUrl,
            size: 44,
            gradient: false,
            borderColor: medal,
            borderWidth: 2,
          ),
          const SizedBox(height: AppSpacing.xs),
          _RankPill(rank: entry.rank, color: medal),
          _MovementChip(
            movement: entry.movement,
            keyPrefix: keyPrefix,
            participantId: entry.participantId,
          ),
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
          Text(
            entry.pointsLabel,
            key: Key('$keyPrefix.points.${entry.participantId}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              color: medal,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (entry.subtitle != null)
            Text(
              entry.subtitle!,
              key: Key('$keyPrefix.entries.${entry.participantId}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: t.textMuted),
            ),
          if (entry.accuracyLabel != null)
            Text(
              entry.accuracyLabel!,
              key: Key('$keyPrefix.accuracy.${entry.participantId}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: t.textMuted),
            ),
        ],
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

    return Container(
      key: Key('$keyPrefix.item.${entry.participantId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMe ? t.surfaceElevated : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isMe ? t.primary : t.border,
          width: isMe ? 1.5 : 1,
        ),
        boxShadow: isMe
            ? <BoxShadow>[
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: -4,
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
              style: context.text.labelLarge?.copyWith(
                color: isMe ? t.primary : t.textMuted,
                fontWeight: FontWeight.w700,
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
            borderWidth: 2,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  entry.displayName,
                  key: Key('$keyPrefix.participant.${entry.participantId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (entry.subtitle != null || entry.accuracyLabel != null)
                  Text(
                    <String>[
                      if (entry.subtitle != null) entry.subtitle!,
                      if (entry.accuracyLabel != null) entry.accuracyLabel!,
                    ].join('  ·  '),
                    key: Key('$keyPrefix.entries.${entry.participantId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _MovementChip(
            movement: entry.movement,
            keyPrefix: keyPrefix,
            participantId: entry.participantId,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            entry.pointsLabel,
            key: Key('$keyPrefix.points.${entry.participantId}'),
            style: context.text.labelLarge?.copyWith(
              color: isMe ? t.primary : t.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The movement arrow: up in success, down in error, and NOTHING at all when
/// the place has not changed or there is no snapshot to compare with.
///
/// An unchanged place used to draw a dash. On the day the first snapshot runs
/// that dash is every row -- the snapshot IS today's board, so every movement
/// is zero -- and a column of identical dashes says nothing while reading as
/// though it does. Absence carries the same meaning without the noise.
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
    if (m == null || m == 0) {
      return const SizedBox.shrink();
    }
    final AppTokens t = context.tokens;
    final Key k = Key('$keyPrefix.movement.$participantId');

    final bool up = m > 0;
    final Color color = up ? t.success : t.error;
    return Row(
      key: k,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 12,
          color: color,
        ),
        Text(
          '${m.abs()}',
          style: context.text.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '$rank',
        style: context.text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "N points to place M" — the one derived number on this screen.
class _GapChip extends StatelessWidget {
  const _GapChip({required this.points, required this.rank});

  final int points;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Align(
      child: Container(
        key: const Key('leaderboard.gapToNext'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: t.primary.withValues(alpha: 0.5)),
        ),
        child: Text(
          '$points نقطة للمرتبة $rank',
          style: context.text.labelMedium?.copyWith(
            color: t.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
