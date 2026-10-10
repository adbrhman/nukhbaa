/// The seated month at a glance: the division, the caller's place, where
/// the month stands, and whether it is the pilot.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/app_badge.dart';
import '../h2h_texts.dart';
import 'h2h_parts.dart';

/// The division card at the top of a seated month.
class H2hDivisionCard extends StatelessWidget {
  /// Creates the card for [league].
  const H2hDivisionCard({required this.league, super.key});

  /// The month as the server sent it.
  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final int level = league.division ?? 4;
    final Color accent = switch (level) {
      1 => t.gold,
      2 => t.silver,
      3 => t.bronze,
      _ => t.primary,
    };
    final int group = league.groupIndex ?? 0;
    final String name = level >= 4 || group > 0
        ? '${h2hDivisionName(level)} · ${h2hGroupName(group)}'
        : h2hDivisionName(level);
    final bool ranked = league.myRank > 0 && h2hAnyPlayed(league);
    final H2hRoundViewDto? current = h2hCurrentRound(league);
    final int? roundNo =
        current?.round ??
        (league.rounds.isEmpty ? null : league.rounds.last.round);
    return Container(
      key: const Key('h2h.banner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_rounded, color: accent, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      key: const Key('h2h.division'),
                      style: context.text.titleMedium?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$h2hLeagueName · ${h2hMonthLabel(league.monthStart)}',
                      key: const Key('h2h.month'),
                      style: context.text.labelMedium?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (league.isPilot) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppBadge(
                key: Key('h2h.pilot'),
                label: 'شهر تجريبي: نتائجه لا تُحتسب',
                tone: AppBadgeTone.gold,
                icon: Icons.science_outlined,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _Stat(
                label: 'مركزك',
                value: ranked
                    ? h2hRankLabel(league.myRank, league.standings.length)
                    : '—',
                valueKey: Key(ranked ? 'h2h.myRank' : 'h2h.myRank.none'),
              ),
              _Stat(
                label: 'الجولة',
                value: roundNo == null
                    ? 'لا جولات بعد'
                    : h2hRoundProgressLabel(roundNo),
                valueKey: const Key('h2h.progress'),
              ),
              _Stat(
                label: 'الشهر',
                value: h2hDaysLeftLabel(league.daysLeft),
                valueKey: const Key('h2h.daysLeft'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One figure of the card: a small label over its value.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            key: valueKey,
            style: context.text.titleSmall?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
