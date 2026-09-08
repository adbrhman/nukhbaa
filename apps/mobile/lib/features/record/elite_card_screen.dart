/// The elite card: one screen that turns a user's season results into an
/// identity rather than a position in someone else's table.
library;

import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/user_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'season_record_providers.dart';

/// Everything the card shows, derived once from the season record.
///
/// A plain value computed in the widget layer, not a domain type: every
/// figure is a fold over rows the server already ruled on (Axiom 2 -- the
/// client computes no points, and none of these are points). Best finish is a
/// minimum over ranks the server assigned; best accuracy a maximum over
/// percentages the server's counts imply.
@immutable
class EliteStats {
  /// Folds [records] into the card's figures.
  factory EliteStats.from(List<MySeasonRecordDto> records) {
    int? bestRank;
    int? bestAccuracy;
    var totalPoints = 0;
    for (final record in records) {
      bestRank = bestRank == null
          ? record.rank
          : math.min(bestRank, record.rank);
      final accuracy = record.accuracyPercent;
      if (accuracy != null) {
        bestAccuracy = bestAccuracy == null
            ? accuracy
            : math.max(bestAccuracy, accuracy);
      }
      totalPoints += record.totalPoints;
    }
    return EliteStats._(
      seasonsPlayed: records.length,
      bestRank: bestRank,
      bestAccuracy: bestAccuracy,
      totalPoints: totalPoints,
      // Oldest first: a trend reads left-to-right in time, and the record
      // arrives newest first.
      rankTrend: <int>[for (final r in records.reversed) r.rank],
    );
  }

  const EliteStats._({
    required this.seasonsPlayed,
    required this.bestRank,
    required this.bestAccuracy,
    required this.totalPoints,
    required this.rankTrend,
  });

  /// How many seasons the user has a result in.
  final int seasonsPlayed;

  /// The best (lowest) place taken, or null with no seasons at all.
  final int? bestRank;

  /// The highest accuracy reached, or null when nothing has settled anywhere.
  final int? bestAccuracy;

  /// Points summed across every season.
  final int totalPoints;

  /// Places taken, oldest season first.
  final List<int> rankTrend;
}

/// Replaces the Hall of Fame tile on the account screen.
class EliteCardScreen extends ConsumerWidget {
  /// Creates the elite card screen for [user].
  const EliteCardScreen({required this.user, super.key});

  /// The signed-in user, passed down rather than re-read: the account screen
  /// already holds it, and a second read of the same profile would be a
  /// second thing to keep in sync with the avatar the user just changed.
  final AuthenticatedUserDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.eliteCard, key: const Key('eliteCard.title')),
      ),
      body: AsyncListView<MySeasonRecordDto>(
        value: ref.watch(mySeasonRecordsProvider),
        emptyMessage: l10n.eliteCardEmpty,
        onRetry: () => ref.invalidate(mySeasonRecordsProvider),
        listBuilder: (context, records) =>
            _CardBody(user: user, stats: EliteStats.from(records)),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.user, required this.stats});

  final AuthenticatedUserDto user;
  final EliteStats stats;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? best = stats.bestRank;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  UserAvatar(
                    displayName: user.displayName,
                    avatarUrl: user.avatarUrl,
                    size: 52,
                    gradient: false,
                    borderColor: t.gold,
                    borderWidth: 2,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.eliteCardSeasonsPlayed(stats.seasonsPlayed),
                          style: context.text.bodySmall?.copyWith(
                            color: t.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Stat(
                      label: l10n.eliteCardBestRank,
                      value: best == null ? '—' : '#$best',
                      color: t.gold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Stat(
                      label: l10n.eliteCardBestAccuracy,
                      value: stats.bestAccuracy == null
                          ? '—'
                          : '${stats.bestAccuracy}%',
                      color: t.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _Stat(
                label: l10n.eliteCardTotalPoints,
                value: l10n.pointsAbbreviated(stats.totalPoints),
                color: t.textPrimary,
              ),
              if (stats.rankTrend.length > 1) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.eliteCardRankTrend,
                  style: context.text.labelSmall?.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 56,
                  child: CustomPaint(
                    painter: _RankTrendPainter(
                      ranks: stats.rankTrend,
                      line: t.primaryLight,
                      dot: t.gold,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Badges(stats: stats),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: 2),
          Text(value, style: context.text.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Paints the rank trend with the axis INVERTED: a better place is higher up.
///
/// Rank 1 is the best result and the smallest number, so plotting it naively
/// would draw improvement as a fall. The line is normalised against the user's
/// own best and worst places rather than a fixed range, so a player who has
/// only ever finished 11th and 14th still sees the shape of their own run.
class _RankTrendPainter extends CustomPainter {
  const _RankTrendPainter({
    required this.ranks,
    required this.line,
    required this.dot,
  });

  final List<int> ranks;
  final Color line;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    if (ranks.length < 2) return;
    final int best = ranks.reduce(math.min);
    final int worst = ranks.reduce(math.max);
    final double span = (worst - best).toDouble();
    final double stepX = size.width / (ranks.length - 1);

    double yFor(int rank) {
      if (span == 0) return size.height / 2;
      return 4 + (rank - best) / span * (size.height - 8);
    }

    final path = Path()..moveTo(0, yFor(ranks.first));
    for (var i = 1; i < ranks.length; i++) {
      path.lineTo(i * stepX, yFor(ranks[i]));
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(size.width, yFor(ranks.last)),
      4.5,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_RankTrendPainter old) =>
      old.ranks != ranks || old.line != line || old.dot != dot;
}

/// Four badges, each unlocked by a figure already on the card.
///
/// Nothing here is awarded by the server, and nothing needs to be: a badge is
/// a restatement of a result the server ruled on, not a new fact. That is
/// exactly why they can be derived client-side without touching Axiom 2 --
/// the moment a badge means something the server did not already say, it
/// belongs in the ledger instead.
class _Badges extends StatelessWidget {
  const _Badges({required this.stats});

  final EliteStats stats;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int rank = stats.bestRank ?? 1 << 30;
    final int accuracy = stats.bestAccuracy ?? 0;

    final badges = <_Badge>[
      _Badge(
        icon: Icons.flag_outlined,
        label: l10n.badgeFirstSeason,
        earned: stats.seasonsPlayed >= 1,
      ),
      _Badge(
        icon: Icons.military_tech_outlined,
        label: l10n.badgeFirstPodium,
        earned: rank <= 3,
      ),
      _Badge(
        icon: Icons.my_location_outlined,
        label: l10n.badgeSharpshooter,
        earned: accuracy >= 50,
      ),
      _Badge(
        icon: Icons.emoji_events_outlined,
        label: l10n.badgeTitleHolder,
        earned: rank == 1,
      ),
    ];

    return Row(
      children: <Widget>[
        for (final badge in badges) ...<Widget>[
          Expanded(child: badge),
          if (badge != badges.last) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.earned});

  final IconData icon;
  final String label;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    // A locked badge is shown, not hidden: knowing what is still out there is
    // the whole reason a badge shelf works.
    return Opacity(
      opacity: earned ? 1 : 0.38,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: t.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              earned ? icon : Icons.lock_outline,
              size: 20,
              color: earned ? t.gold : t.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: earned ? t.textSecondary : t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
