/// The home page's duels card: a challenge waiting for the caller, the
/// duels still running, and the last result. It shows only when one of
/// those exists, and is the duel channel for players without push (the web
/// build): they learn of a challenge here.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import 'duel_texts.dart';
import 'duels_providers.dart';
import 'duels_screen.dart';

/// How long a settled duel stays on the card after its kickoff.
const Duration duelResultShownFor = Duration(days: 3);

/// What the card says, from the caller's challenges and duels.
final class DuelsHomeSummary {
  /// Builds the summary of [mine] as of [now].
  factory DuelsHomeSummary.of(MyDuelsDto mine, DateTime now) {
    final List<DuelChallengeDto> invitations = <DuelChallengeDto>[
      for (final DuelChallengeDto c in mine.challenges)
        if (c.isForMe && c.state == 'open') c,
    ];
    int running = 0;
    DuelSummaryDto? lastResult;
    for (final DuelSummaryDto d in mine.duels) {
      if (d.state == 'upcoming' || d.state == 'live') {
        running++;
      } else if (d.state == 'settled' && d.outcome != null) {
        final DateTime? kickoff = DateTime.tryParse(d.kickoffAt)?.toUtc();
        if (kickoff == null || now.difference(kickoff) > duelResultShownFor) {
          continue;
        }
        final DateTime? best = lastResult == null
            ? null
            : DateTime.tryParse(lastResult.kickoffAt)?.toUtc();
        if (best == null || kickoff.isAfter(best)) lastResult = d;
      }
    }
    return DuelsHomeSummary._(invitations, running, lastResult);
  }

  const DuelsHomeSummary._(this.invitations, this.running, this.lastResult);

  /// Open challenges addressed to the caller.
  final List<DuelChallengeDto> invitations;

  /// Duels that have not finished.
  final int running;

  /// The latest settled duel, if recent.
  final DuelSummaryDto? lastResult;

  /// Nothing to say: the card stays hidden.
  bool get isEmpty => invitations.isEmpty && running == 0 && lastResult == null;
}

/// The card; renders nothing while loading, on error, or when empty.
class DuelsHomeCard extends ConsumerWidget {
  /// Creates the card.
  const DuelsHomeCard({this.now, super.key});

  /// The clock, for tests.
  final DateTime? now;

  void _open(BuildContext context, {String? code}) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => DuelsScreen(openCode: code)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MyDuelsDto? mine = ref.watch(myDuelsProvider).value;
    if (mine == null) return const SizedBox.shrink();
    final DuelsHomeSummary summary = DuelsHomeSummary.of(
      mine,
      (now ?? DateTime.now()).toUtc(),
    );
    if (summary.isEmpty) return const SizedBox.shrink();

    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final DuelChallengeDto? invitation = summary.invitations.isEmpty
        ? null
        : summary.invitations.first;
    final DuelSummaryDto? result = summary.lastResult;
    final TextStyle? line = text.bodyMedium?.copyWith(
      color: tokens.textSecondary,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        key: const Key('home.duels'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: AppRadius.brCard,
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.compare_arrows_rounded, color: tokens.primaryText),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'مواجهاتك',
                    style: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('home.duels.all'),
                  onPressed: () => _open(context),
                  child: const Text('الكل'),
                ),
              ],
            ),
            if (invitation != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${invitation.challengerName} يتحداك',
                key: const Key('home.duels.invitation'),
                style: text.titleSmall?.copyWith(color: tokens.textPrimary),
              ),
              Text(
                duelFixtureTitle(invitation.homeTeam, invitation.awayTeam),
                style: line,
              ),
              if (summary.invitations.length > 1)
                Text(
                  'تحديات أخرى بانتظارك: '
                  '${summary.invitations.length - 1}',
                  style: line,
                ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                key: const Key('home.duels.accept'),
                onPressed: () => _open(context, code: invitation.code),
                child: const Text('توقّع واقبل'),
              ),
            ],
            if (summary.running > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'مواجهات جارية: ${summary.running}',
                key: const Key('home.duels.running'),
                style: line,
              ),
            ],
            if (result != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${duelOutcomeLabel(result.outcome!)} أمام '
                '${result.opponentName} '
                '(${result.myPoints ?? 0}-${result.opponentPoints ?? 0})',
                key: const Key('home.duels.result'),
                style: line,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
