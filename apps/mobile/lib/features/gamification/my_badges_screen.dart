/// The badge wall: every catalog badge with the caller's progress, read from
/// `GET /me/badges` (P2-8).
///
/// The server counts and grants; this screen only draws. A badge is held
/// when the server sent the moment it was granted, and a code this build
/// does not know yet is skipped rather than drawn without a name.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';

/// `GET /me/badges` -- the caller's badge wall.
final myBadgesProvider = FutureProvider.autoDispose<MyBadgesDto>((ref) async {
  final api = ref.watch(authApiProvider);
  return switch (await api.myBadges()) {
    Ok<MyBadgesDto>(:final value) => value,
    Err<MyBadgesDto>(:final error) => throw error,
  };
});

/// The words and the picture of one catalog badge.
typedef BadgeLook = ({String name, String description, IconData icon});

/// How the badge stored as [code] is drawn, or null for a code this build
/// does not know.
BadgeLook? badgeLookOf(AppLocalizations l10n, String code) => switch (code) {
  'first_prediction' => (
    name: l10n.badgeWallFirstPredictionName,
    description: l10n.badgeWallFirstPredictionHint,
    icon: Icons.flag_rounded,
  ),
  'predictions_25' => (
    name: l10n.badgeWallPredictions25Name,
    description: l10n.badgeWallPredictions25Hint,
    icon: Icons.edit_note_rounded,
  ),
  'predictions_100' => (
    name: l10n.badgeWallPredictions100Name,
    description: l10n.badgeWallPredictions100Hint,
    icon: Icons.military_tech_rounded,
  ),
  'first_perfect_day' => (
    name: l10n.badgeWallFirstPerfectDayName,
    description: l10n.badgeWallFirstPerfectDayHint,
    icon: Icons.check_circle_rounded,
  ),
  'perfect_days_7' => (
    name: l10n.badgeWallPerfectDays7Name,
    description: l10n.badgeWallPerfectDays7Hint,
    icon: Icons.local_fire_department_rounded,
  ),
  'perfect_days_30' => (
    name: l10n.badgeWallPerfectDays30Name,
    description: l10n.badgeWallPerfectDays30Hint,
    icon: Icons.whatshot_rounded,
  ),
  'league_first_week' => (
    name: l10n.badgeWallLeagueFirstWeekName,
    description: l10n.badgeWallLeagueFirstWeekHint,
    icon: Icons.shield_rounded,
  ),
  'league_promoted' => (
    name: l10n.badgeWallLeaguePromotedName,
    description: l10n.badgeWallLeaguePromotedHint,
    icon: Icons.trending_up_rounded,
  ),
  'league_champion' => (
    name: l10n.badgeWallLeagueChampionName,
    description: l10n.badgeWallLeagueChampionHint,
    icon: Icons.emoji_events_rounded,
  ),
  'league_elite' => (
    name: l10n.badgeWallLeagueEliteName,
    description: l10n.badgeWallLeagueEliteHint,
    icon: Icons.workspace_premium_rounded,
  ),
  _ => null,
};

/// The badge wall page.
class MyBadgesScreen extends ConsumerWidget {
  /// Creates the page.
  const MyBadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.myBadges, key: const Key('badges.title')),
      ),
      body: AsyncObjectView<MyBadgesDto>(
        value: ref.watch(myBadgesProvider),
        onRetry: () => ref.invalidate(myBadgesProvider),
        builder: (context, wall) {
          final List<(BadgeDto, BadgeLook)> known = <(BadgeDto, BadgeLook)>[
            for (final BadgeDto badge in wall.badges)
              if (badgeLookOf(l10n, badge.code) case final BadgeLook look)
                (badge, look),
          ];
          final int held = known
              .where((item) => item.$1.unlockedAt != null)
              .length;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              Text(
                l10n.badgeWallSummary(held, known.length),
                key: const Key('badges.summary'),
                textAlign: TextAlign.center,
                style: context.text.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (BadgeDto badge, BadgeLook look) in known) ...<Widget>[
                _BadgeTile(badge: badge, look: look),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.look});

  final BadgeDto badge;
  final BadgeLook look;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();
    final String? unlockedAt = badge.unlockedAt;
    final DateTime? granted = unlockedAt == null
        ? null
        : DateTime.tryParse(unlockedAt)?.toLocal();
    final bool isHeld = unlockedAt != null;
    final Color accent = isHeld ? t.gold : t.textMuted;
    final int target = badge.target <= 0 ? 1 : badge.target;
    final double ratio = badge.current <= 0
        ? 0.0
        : (badge.current >= target ? 1.0 : badge.current / target);

    return Container(
      key: Key('badges.item.${badge.code}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: isHeld ? t.gold.withValues(alpha: 0.7) : t.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
            child: Icon(look.icon, color: accent, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  look.name,
                  key: Key('badges.name.${badge.code}'),
                  style: context.text.titleSmall?.copyWith(
                    color: isHeld ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  look.description,
                  style: context.text.bodySmall?.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (isHeld)
                  Text(
                    granted == null
                        ? l10n.badgeWallHeld
                        : l10n.badgeWallUnlockedOn(
                            intl.DateFormat(
                              'd MMMM yyyy',
                              locale,
                            ).format(granted),
                          ),
                    key: Key('badges.unlocked.${badge.code}'),
                    style: context.text.labelSmall?.copyWith(
                      color: t.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppRadius.brXs,
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            color: t.primary,
                            backgroundColor: t.border,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.badgeWallProgress(badge.current, target),
                        key: Key('badges.progress.${badge.code}'),
                        style: context.text.labelSmall?.copyWith(
                          color: t.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
