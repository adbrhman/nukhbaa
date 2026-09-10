// ignore_for_file: sort_child_properties_last
/// The presentation for the ranked board.
///
/// The main leaderboards tab uses the reference-style mobile layout:
/// cosmic header, season selector, segmented scope, summary metrics, podium,
/// update/gap strip, and a compact ranked table. The ranking values remain
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
    this.movement,
    this.accuracyLabel,
    this.avatarUrl,
  });

  final String participantId;
  final int rank;
  final String displayName;
  final int points;
  final String pointsLabel;
  final String? subtitle;
  final int? movement;
  final String? accuracyLabel;
  final String? avatarUrl;
}

class LeaderboardBoard extends StatelessWidget {
  const LeaderboardBoard({
    required this.entries,
    required this.keyPrefix,
    this.myParticipantId,
    this.myDisplayName,
    this.competitionName,
    this.seasonLabel,
    this.startAt,
    this.endAt,
    this.showHeader = false,
    this.onRefresh,
    this.onBack,
    super.key,
  });

  final List<BoardEntry> entries;
  final String keyPrefix;
  final String? myParticipantId;
  final String? myDisplayName;
  final String? competitionName;
  final String? seasonLabel;
  final String? startAt;
  final String? endAt;
  final bool showHeader;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final BoardEntry? viewer = _findViewer();
    final List<BoardEntry> podium = entries.take(3).toList(growable: false);
    final List<BoardEntry> rest = entries.skip(3).toList(growable: false);
    final int viewerIndex = viewer == null
        ? -1
        : entries.indexWhere(
            (entry) => entry.participantId == viewer.participantId,
          );
    final int? gapToAbove = viewerIndex > 0
        ? entries[viewerIndex - 1].points - viewer!.points
        : null;

    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        showHeader ? 0 : AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl + bottomInset,
      ),
      children: <Widget>[
        if (showHeader) ...<Widget>[
          _ReferenceHeader(
            competitionName: competitionName,
            seasonLabel: seasonLabel,
            startAt: startAt,
            endAt: endAt,
            onRefresh: onRefresh,
            onBack: onBack,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ScopeTabs(
            onFriendsTap: () => _showDisabledScope(context),
            onEliteTap: () => _showDisabledScope(context),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (showHeader) _SummaryCard(viewer: viewer),
        if (showHeader) const SizedBox(height: AppSpacing.sm),
        if (podium.isNotEmpty)
          _Podium(
            entries: podium,
            keyPrefix: keyPrefix,
            myParticipantId: viewer?.participantId,
          ),
        if (gapToAbove != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _BoardMetaStrip(
            gapPoints: gapToAbove,
            targetRank: entries[viewerIndex - 1].rank,
          ),
        ] else if (showHeader && entries.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          const _BoardMetaStrip(),
        ],
        if (rest.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _TableHeader(),
          const SizedBox(height: 4),
          for (final BoardEntry entry in rest)
            _BoardRow(
              entry: entry,
              keyPrefix: keyPrefix,
              isMe: entry.participantId == viewer?.participantId,
            ),
        ],
      ],
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
    for (final BoardEntry entry in entries) {
      if (entry.displayName.trim() == name) return entry;
    }
    return null;
  }

  void _showDisabledScope(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('هذه القائمة ستتوفر قريبًا.')));
  }
}

class _ReferenceHeader extends StatelessWidget {
  const _ReferenceHeader({
    required this.competitionName,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
    required this.onRefresh,
    required this.onBack,
  });

  final String? competitionName;
  final String? seasonLabel;
  final String? startAt;
  final String? endAt;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 78,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppRadius.xl),
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.05, -0.4),
                        radius: 1.15,
                        colors: <Color>[
                          t.primary.withValues(alpha: 0.38),
                          t.primary.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const <double>[0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          const Color(0xFF06152B).withValues(alpha: 0.92),
                          t.background.withValues(alpha: 0.98),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(left: 34, top: 22, child: _StarDot(size: 2)),
                const Positioned(left: 82, top: 42, child: _StarDot(size: 3)),
                const Positioned(left: 128, top: 23, child: _StarDot(size: 2)),
                const Positioned(right: 52, top: 30, child: _StarDot(size: 3)),
                const Positioned(right: 118, top: 52, child: _StarDot(size: 2)),
                const Positioned(right: 170, top: 24, child: _StarDot(size: 2)),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: t.gold,
                      size: 22,
                    ),
                  ),
                ),
                Positioned(
                  top: 9,
                  left: 34,
                  child: IconButton(
                    tooltip: 'تحديث',
                    onPressed: onRefresh,
                    icon: const Icon(
                      Icons.filter_alt_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
                Positioned(
                  top: 9,
                  right: 34,
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                Positioned.fill(
                  top: 14,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'المتصدرون',
                        style: context.text.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 23,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'من يتصدر الترتيب هذا الشهر؟',
                        style: context.text.labelSmall?.copyWith(
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SeasonSelector(
          competitionName: competitionName,
          seasonLabel: seasonLabel,
          startAt: startAt,
          endAt: endAt,
        ),
      ],
    );
  }
}

class _StarDot extends StatelessWidget {
  const _StarDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.competitionName,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
  });

  final String? competitionName;
  final String? seasonLabel;
  final String? startAt;
  final String? endAt;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.calendar_month_rounded, color: t.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  competitionName?.trim().isNotEmpty == true
                      ? competitionName!
                      : 'موسم التوقعات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _rangeText(startAt, endAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            seasonLabel ?? 'الشهر الحالي',
            style: context.text.labelSmall?.copyWith(
              color: t.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, color: t.textMuted),
        ],
      ),
    );
  }

  String _rangeText(String? startAt, String? endAt) {
    final DateTime? start = DateTime.tryParse(startAt ?? '');
    DateTime? end = DateTime.tryParse(endAt ?? '');
    if (start == null || end == null) return 'الفترة الحالية';
    end = end.subtract(const Duration(days: 1));
    const months = <String>[
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final String month = months[end.month];
    return '${start.day} - ${end.day} $month ${end.year}';
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.onFriendsTap, required this.onEliteTap});

  final VoidCallback onFriendsTap;
  final VoidCallback onEliteTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    Widget segment({
      required String label,
      required bool active,
      VoidCallback? onTap,
      IconData? icon,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? t.primary : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 14,
                    color: active ? Colors.white : t.textMuted,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: active ? Colors.white : t.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: <Widget>[
          segment(
            label: 'الشهر',
            active: true,
            icon: Icons.calendar_month_rounded,
          ),
          segment(
            label: 'أصدقائي',
            active: false,
            onTap: onFriendsTap,
            icon: Icons.group_rounded,
          ),
          segment(
            label: 'النخبة',
            active: false,
            onTap: onEliteTap,
            icon: Icons.workspace_premium_outlined,
          ),
        ],
      ),
    );
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
  const _BoardMetaStrip({this.gapPoints, this.targetRank});

  final int? gapPoints;
  final int? targetRank;

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
        if (gapPoints != null && targetRank != null)
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
              '$gapPoints نقطة للوصول للمرتبة $targetRank',
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
    final String matches = _matchesFromSubtitle(entry.subtitle);

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
            child: _MovementChip(
              movement: entry.movement,
              keyPrefix: keyPrefix,
              participantId: entry.participantId,
            ),
          ),
        ],
      ),
    );
  }

  String _matchesFromSubtitle(String? subtitle) {
    if (subtitle == null || subtitle.isEmpty) return '—';
    final Match? match = RegExp(r'\d+').firstMatch(subtitle);
    return match?.group(0) ?? '—';
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
