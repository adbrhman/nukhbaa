/// The third section of a seated month: every approved round, the newest
/// first, each with its opponent, its points and its phase as the server
/// sent it (open, upcoming, live, settled or voided).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../h2h_round_screen.dart';
import '../h2h_texts.dart';
import 'h2h_next_match.dart';
import 'h2h_parts.dart';

/// The rounds of the month.
class H2hRoundsList extends StatelessWidget {
  /// Creates the list for [league].
  const H2hRoundsList({required this.league, super.key});

  /// The month as the server sent it.
  final MyH2hLeagueDto league;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const H2hSectionTitle(text: 'الجولات', key: Key('h2h.rounds.title')),
        const SizedBox(height: AppSpacing.sm),
        if (league.rounds.isEmpty)
          const H2hNoRounds()
        else
          for (final H2hRoundViewDto r in league.rounds.reversed) ...<Widget>[
            MergeSemantics(
              child: H2hOpenRound(
                round: r.round,
                child: H2hRoundTile(round: r),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        if (league.rounds.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            h2hRoundsNote,
            key: const Key('h2h.rounds.note'),
            style: context.text.bodySmall?.copyWith(
              color: context.tokens.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// One round of the month as the caller plays it.
class H2hRoundTile extends StatelessWidget {
  /// Creates the tile.
  const H2hRoundTile({required this.round, super.key});

  /// The round as the server sent it.
  final H2hRoundViewDto round;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool current = round.status == 'open' || round.status == 'live';
    final bool scored = round.myPoints != null;
    final bool showResult =
        round.result != null &&
        (round.status == 'settled' || round.status == 'live');
    return Container(
      key: Key('h2h.round.${round.round}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(
          color: current ? t.primary.withValues(alpha: 0.7) : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  'الجولة ${round.round} · ${h2hDayLabel(round.day)}',
                  style: context.text.labelMedium?.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              H2hStatusChip(
                key: Key('h2h.round.${round.round}.status'),
                status: round.status,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            round.status == 'voided'
                ? 'لم تبقَ فيها مباراة تُحتسب'
                : 'ضد ${h2hOpponentOf(round)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (scored || showResult) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (scored)
                  Text(
                    '${h2hPointsLabel(round.myPoints!)} مقابل '
                    '${h2hPointsLabel(round.opponentPoints ?? 0)}',
                    key: Key('h2h.round.${round.round}.score'),
                    style: context.text.titleSmall?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (showResult)
                  H2hResultBadge(
                    result: round.result!,
                    live: round.status == 'live',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
