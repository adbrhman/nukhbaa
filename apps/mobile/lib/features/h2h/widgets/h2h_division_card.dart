/// The seated month at a glance: the caller's place and the gap to the
/// place above first, then the round that matters now and the time left;
/// the division is a compact header and the pilot rule a quiet footnote.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
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
    // Icon, rim and wash only, never text: the medal gold, not the text gold
    // that reads olive in the light theme.
    final Color accent = switch (level) {
      1 => t.goldAccent,
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
    final H2hStandingDto? me = h2hMyStanding(league);
    final H2hStandingDto? above = _placeAbove(league);
    final int count = league.standings.length;
    // The zones only mean something in a month whose results count.
    final bool promoted =
        ranked &&
        !league.isPilot &&
        league.promotionZone > 0 &&
        league.myRank <= league.promotionZone;
    final bool relegated =
        ranked &&
        !league.isPilot &&
        !promoted &&
        league.relegationZone > 0 &&
        league.myRank > count - league.relegationZone;
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
          // Which division and group: a compact header, the place below it
          // is what the player reads first.
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  // The first division sits on amber: a gold wash read
                  // grey on the navy (CA-19).
                  color: level == 1
                      ? t.goldContainer
                      : accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_rounded, color: accent, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      key: const Key('h2h.division'),
                      style: context.text.titleSmall?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$h2hLeagueName · ${h2hMonthLabel(league.monthStart)}',
                      key: const Key('h2h.month'),
                      style: context.text.labelSmall?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // nk-h2h-glance: the place, the gap to the place above and the
          // zone, in the largest type on the card.
          Container(
            key: const Key('h2h.glance'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: t.surfaceElevated,
              borderRadius: AppRadius.brMd,
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'مركزك',
                      style: context.text.labelMedium?.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      ranked ? h2hRankLabel(league.myRank, count) : '—',
                      key: Key(ranked ? 'h2h.myRank' : 'h2h.myRank.none'),
                      style: context.text.headlineMedium?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
                if (ranked && me != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _Pill(
                        textKey: const Key('h2h.gap'),
                        text: h2hGapLabel(
                          myRank: league.myRank,
                          aboveRank: above?.rank,
                          gap: above == null
                              ? 0
                              : above.leaguePoints - me.leaguePoints,
                        ),
                        fg: league.myRank == 1 ? t.gold : t.primaryText,
                        bg: league.myRank == 1
                            ? t.goldContainer
                            : t.primary.withValues(alpha: 0.14),
                      ),
                      if (promoted || relegated) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        _Pill(
                          textKey: Key(
                            promoted
                                ? 'h2h.zone.promotion'
                                : 'h2h.zone.relegation',
                          ),
                          text: promoted
                              ? h2hInPromotionZone
                              : h2hInRelegationZone,
                          fg: promoted ? t.successText : t.errorText,
                          bg: promoted ? t.successContainer : t.errorContainer,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The round that matters now and the time left, side by side.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: 'الجولة الحالية',
                  value: roundNo == null
                      ? 'لا جولات بعد'
                      : h2hRoundProgressLabel(roundNo),
                  valueKey: const Key('h2h.progress'),
                  note: roundNo == null ? null : h2hRoundCapLabel,
                  noteKey: const Key('h2h.progress.cap'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(
                  label: 'الوقت المتبقي',
                  value: h2hDaysLeftLabel(league.daysLeft),
                  valueKey: const Key('h2h.daysLeft'),
                  note: 'حتى نهاية الشهر',
                  noteKey: const Key('h2h.daysLeft.note'),
                ),
              ),
            ],
          ),
          // A rule of the month, not the player's state: a quiet line at
          // the foot of the card.
          if (league.isPilot) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              key: const Key('h2h.pilot'),
              children: <Widget>[
                Icon(
                  Icons.science_outlined,
                  size: AppSizes.iconXs,
                  color: t.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'شهر تجريبي: نتائجه لا تُحتسب',
                    style: context.text.labelSmall?.copyWith(
                      color: t.textSecondary,
                    ),
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

/// The line of the table just above the caller's, by the server's ranks;
/// null for the leader or a caller with no line.
H2hStandingDto? _placeAbove(MyH2hLeagueDto league) {
  final H2hStandingDto? me = h2hMyStanding(league);
  if (me == null || me.rank <= 1) return null;
  H2hStandingDto? above;
  for (final H2hStandingDto s in league.standings) {
    if (s.rank < me.rank && (above == null || s.rank > above.rank)) {
      above = s;
    }
  }
  return above;
}

/// A short coloured line: the gap, or the zone.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.fg,
    required this.bg,
    required this.textKey,
  });

  final String text;

  /// On the words, so a reader of the card finds them.
  final Key textKey;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
    ),
    child: Text(
      text,
      key: textKey,
      style: context.text.labelMedium?.copyWith(
        color: fg,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// One figure of the card: a small label over its value.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.valueKey,
    this.note,
    this.noteKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  /// A smaller line under the value: a rule, never the player's state.
  final String? note;
  final Key? noteKey;

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
            style: context.text.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (note != null)
            Text(
              note!,
              key: noteKey,
              style: context.text.labelSmall?.copyWith(color: t.textSecondary),
            ),
        ],
      ),
    );
  }
}
