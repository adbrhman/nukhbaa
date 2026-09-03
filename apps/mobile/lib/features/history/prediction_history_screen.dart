library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/team_logo.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_registry.dart';
import '../competition/widgets/async_list_view.dart';
import 'fixture_scores_providers.dart';
import 'prediction_history_providers.dart';

/// The caller's own aggregated prediction history — every per-fixture
/// prediction they have ever submitted, across every fixture and season,
/// newest first. The retired round-scoped history (`GET /me/predictions`)
/// is no longer shown here (docs/project-context.md, "Legacy `Round`
/// predictions in `prediction_history_screen.dart`" — the app has not
/// launched yet, so there was no external history to preserve).
///
/// Shows each historical forecast (its fixture scoreline and submission
/// time), plus a correctness badge (✅/❌/🔥) once [fixtureScoresProvider]
/// resolves a grade for it.
class PredictionHistoryScreen extends ConsumerWidget {
  const PredictionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<FixturePredictionDto>> history = ref.watch(
      myFixturePredictionsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myPredictions, key: const Key('history.title')),
      ),
      body: AsyncListView<FixturePredictionDto>(
        value: history,
        emptyMessage: l10n.predictionHistoryEmpty,
        onRetry: () => ref.invalidate(myFixturePredictionsProvider),
        itemBuilder: (context, prediction) =>
            _FixturePredictionCard(prediction: prediction),
      ),
    );
  }
}

/// A single historical per-fixture forecast (Axiom 4 Amendment).
///
/// There is no season/round context to resolve team names from here —
/// [FixturePredictionDto] carries only the fixture id — so the score line
/// always falls back to the raw fixture id (the same fallback [_ScoreLine]
/// renders whenever it isn't given a resolved [RoundFixtureCardDto]). The
/// grade badge (✅/❌/🔥), when shown, comes from [fixtureScoresProvider] —
/// only queried when [FixturePredictionDto.seasonId] is populated. A `null`
/// seasonId, a still-loading read, or any read error all degrade the same
/// way: no badge, never a broken card.
class _FixturePredictionCard extends ConsumerWidget {
  const _FixturePredictionCard({required this.prediction});
  final FixturePredictionDto prediction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final String? seasonId = prediction.seasonId;
    final AsyncValue<FixtureScoresDto>? scoresAsync = seasonId == null
        ? null
        : ref.watch(fixtureScoresProvider(seasonId, prediction.fixtureId));
    String? grade;
    for (final ParticipantFixtureScoreDto s
        in scoresAsync?.value?.scores ?? const []) {
      if (s.participantId == prediction.participantId) {
        grade = s.grade;
        break;
      }
    }
    return Card(
      key: Key('history.item.${prediction.id}'),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              prediction.submittedAt,
              key: Key('history.submittedAt.${prediction.id}'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _ScoreLine(
                key: Key(
                  'history.score.${prediction.id}.${prediction.fixtureId}',
                ),
                score: FixtureScoreDto(
                  fixtureId: prediction.fixtureId,
                  homeGoals: prediction.homeGoals,
                  awayGoals: prediction.awayGoals,
                  isDouble: prediction.isDouble,
                ),
                fixture: null,
                grade: grade,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One fixture's scoreline: "[crest] Home  2 - 1  Away [crest]". Falls back to
/// the raw fixture id (no crests) when [fixture] is `null` — the resolved read
/// hasn't returned this fixture yet, or it is no longer linked to the round.
class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.score,
    required this.fixture,
    this.grade,
    super.key,
  });

  final FixtureScoreDto score;
  final RoundFixtureCardDto? fixture;
  final String? grade;

  /// The small correctness badge, or `null` when the round isn't scored yet
  /// or this fixture was `missed`.
  String? get _badge {
    switch (grade) {
      case 'exact_scoreline':
        return score.isDouble ? '🔥' : '✅';
      case 'correct_outcome':
      case 'incorrect':
        return '❌';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RoundFixtureCardDto? f = fixture;
    final bool hasNames =
        (f?.homeTeam?.isNotEmpty ?? false) &&
        (f?.awayTeam?.isNotEmpty ?? false);
    final String? badge = _badge;

    if (!hasNames) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.predictionHistoryScoreLine(
              score.fixtureId,
              score.homeGoals,
              score.awayGoals,
            ),
          ),
          if (badge != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(badge, style: const TextStyle(fontSize: 11)),
            ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: _TeamMini(name: f!.homeTeam, alignEnd: false)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ScorePill(home: score.homeGoals, away: score.awayGoals),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(badge, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Expanded(child: _TeamMini(name: f.awayTeam, alignEnd: true)),
      ],
    );
  }
}

/// A compact crest + display name for one side of a score line.
class _TeamMini extends StatelessWidget {
  const _TeamMini({required this.name, required this.alignEnd});

  final String? name;
  final bool alignEnd;

  static const double _crestSize = 22;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TeamBrand? brand = lookupTeam(name);
    final String display = teamDisplayName(name);
    final Widget crest = TeamLogo(
      displayName: display,
      crestUrl: brand?.logoUrl,
      brandColor: brand?.c1,
      size: _crestSize,
    );
    final Text label = Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
    );

    final List<Widget> children = alignEnd
        ? <Widget>[Expanded(child: label), const SizedBox(width: 6), crest]
        : <Widget>[crest, const SizedBox(width: 6), Expanded(child: label)];

    return Row(children: children);
  }
}

/// The centered "2 - 1" pill between the two [_TeamMini]s.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.home, required this.away});

  final int home;
  final int away;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        '$home - $away',
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
