/// Today's challenge, and the run of days behind it.
///
/// Two readings of the caller's own day: how much of it they have covered
/// (`GET /me/daily-challenge`) and their run of completed days
/// (`GET /me/streak`). Both are counted server-side on every call, so nothing
/// is cached here that could drift from the record, and the day boundary
/// stays the server's Riyadh day.
///
/// Silent while it loads, silent when the request fails, and silent on a rest
/// day with no run to show: a home page is not the place to tell someone they
/// have nothing.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../core/ui/app_card.dart';
import '../../l10n/app_localizations.dart';

/// The home page's daily-challenge card.
class DailyChallengeCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const DailyChallengeCard({required this.onOpenMatches, super.key});

  /// Opens the matches tab, where the day's fixtures are predicted.
  final VoidCallback onOpenMatches;

  @override
  ConsumerState<DailyChallengeCard> createState() => _DailyChallengeCardState();
}

class _DailyChallengeCardState extends ConsumerState<DailyChallengeCard> {
  MyDailyChallengeDto? _challenge;
  MyStreakDto? _streak;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Fetched once per mount rather than through a provider: both numbers move
  /// only when a prediction lands, and a pull to refresh rebuilds this card
  /// with the rest of the page.
  Future<void> _load() async {
    final AuthApi api = ref.read(authApiProvider);
    final Result<MyDailyChallengeDto> challenge = await api.myDailyChallenge();
    final Result<MyStreakDto> streak = await api.myStreak();
    if (!mounted) {
      return;
    }
    setState(() {
      if (challenge is Ok<MyDailyChallengeDto>) {
        _challenge = challenge.value;
      }
      if (streak is Ok<MyStreakDto>) {
        _streak = streak.value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MyDailyChallengeDto? challenge = _challenge;
    final MyStreakDto? streak = _streak;
    final int current = streak?.current ?? 0;
    if (challenge == null) {
      return const SizedBox.shrink();
    }
    if (challenge.total == 0 && current == 0) {
      return const SizedBox.shrink();
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final bool empty = challenge.total == 0;
    final bool complete = challenge.complete;
    double fraction = 0;
    if (!empty) {
      fraction = challenge.predicted / challenge.total;
      if (fraction > 1) {
        fraction = 1;
      }
    }
    final String line;
    if (empty) {
      line = l10n.dailyChallengeEmpty;
    } else if (complete) {
      line = l10n.dailyChallengeComplete;
    } else {
      line = l10n.dailyChallengeCta;
    }

    return AppCard(
      key: const Key('home.dailyChallenge'),
      onTap: empty || complete ? null : widget.onOpenMatches,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // P1-7: a completed day lands with a small pop.
              TweenAnimationBuilder<double>(
                key: ValueKey<bool>(complete),
                tween: Tween<double>(begin: complete ? 0.4 : 1, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(
                  complete ? Icons.task_alt_rounded : Icons.today_rounded,
                  size: 18,
                  color: complete ? tokens.success : tokens.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.dailyChallengeTitle,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (current > 0) _StreakBadge(days: current),
            ],
          ),
          if (!empty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ColoredBox(color: tokens.surfaceHigh),
                    ),
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: fraction,
                        child: ColoredBox(
                          color: complete ? tokens.success : tokens.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  line,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
              ),
              if (!empty)
                Text(
                  l10n.dailyChallengeProgress(
                    challenge.predicted,
                    challenge.total,
                  ),
                  key: const Key('home.dailyChallenge.count'),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          if (streak != null && streak.longest > current) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.streakLongestLabel(streak.longest),
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// The run of completed match days, as a badge on the card's title row.
///
/// A number, not a sentence: Arabic counts its own way past ten, and a badge
/// that reads "Streak: 12" needs no counted noun to be understood.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      key: const Key('home.dailyChallenge.streak'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.local_fire_department_rounded,
            size: 14,
            color: tokens.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).streakBadgeLabel(days),
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
