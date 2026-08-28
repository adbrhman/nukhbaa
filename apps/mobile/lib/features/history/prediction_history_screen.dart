library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../competition/team_registry.dart';
import '../competition/widgets/async_list_view.dart';
import 'prediction_history_providers.dart';
import 'round_scores_providers.dart';

/// The caller's own aggregated prediction history — every prediction they
/// have ever submitted, across every round and season, newest first.
///
/// Shows each historical forecast (its fixture scorelines and submission
/// time). Win/loss status is intentionally NOT shown here: that requires
/// cross-referencing each fixture's recorded result
/// (`GET /rounds/{id}/scores`) per round, which is a separate, heavier read
/// this screen does not perform — a future pass can enrich each row with it.
class PredictionHistoryScreen extends ConsumerWidget {
  const PredictionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<PredictionHistoryEntry>> history = ref.watch(
      predictionHistoryProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myPredictions, key: const Key('history.title')),
      ),
      body: AsyncListView<PredictionHistoryEntry>(
        value: history,
        emptyMessage: l10n.predictionHistoryEmpty,
        onRetry: () => ref.invalidate(predictionHistoryProvider),
        itemBuilder: (context, entry) => switch (entry) {
          RoundPredictionEntry(:final prediction) => _PredictionCard(
            prediction: prediction,
          ),
          FixturePredictionEntry(:final prediction) => _FixturePredictionCard(
            prediction: prediction,
          ),
        },
      ),
    );
  }
}

/// A single historical forecast. Resolves its fixtures' team identity via
/// `roundFixturesProvider(prediction.roundId)` — the same read
/// `RoundFixturesScreen` uses — so a score line renders as "Home 2 - 1 Away"
/// (with crests) instead of the opaque fixture id. A fixture that cannot be
/// resolved (the round read is still loading, failed, or the fixture is no
/// longer linked) falls back to the raw id — the card never hides a score
/// line just because its team identity is unavailable.
class _PredictionCard extends ConsumerWidget {
  const _PredictionCard({required this.prediction});
  final PredictionDto prediction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AsyncValue<List<RoundFixtureCardDto>> fixtures = ref.watch(
      roundFixturesProvider(prediction.roundId),
    );
    // Best-effort lookup map: while [fixtures] is loading or failed, every
    // score line simply falls back to its raw fixture id (see
    // [_ScoreLine.build]) rather than blocking or erroring the whole card.
    final Map<String, RoundFixtureCardDto> byFixtureId =
        <String, RoundFixtureCardDto>{
          for (final RoundFixtureCardDto fixture in fixtures.value ?? const [])
            fixture.fixtureId: fixture,
        };
    final AsyncValue<RoundScoresDto?> roundScoresAsync = ref.watch(
      roundScoresProvider(prediction.roundId),
    );
    RoundScoreDto? myScore;
    for (final RoundScoreDto s in roundScoresAsync.value?.scores ?? const []) {
      if (s.participantId == prediction.participantId) {
        myScore = s;
        break;
      }
    }
    final Map<String, String> gradeByFixtureId = <String, String>{
      for (final FixtureScoreResultDto r in myScore?.fixtureResults ?? const [])
        r.fixtureId: r.grade,
    };

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
            for (final FixtureScoreDto score in prediction.fixtureScores)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _ScoreLine(
                  key: Key('history.score.${prediction.id}.${score.fixtureId}'),
                  score: score,
                  fixture: byFixtureId[score.fixtureId],
                  grade: gradeByFixtureId[score.fixtureId],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single historical **per-fixture** forecast (Axiom 4 Amendment; the
/// per-fixture sibling of [_PredictionCard]).
///
/// Unlike [_PredictionCard], there is no known season/round context to
/// resolve team names from here — [FixturePredictionDto] carries only the
/// fixture id — so the score line always falls back to the raw fixture id
/// (the same fallback [_ScoreLine] already renders while its round-fixtures
/// read is loading or unresolved). There is also no grade badge yet: the
/// per-fixture score read (`GetFixtureScores`) has no `api_client` method
/// wired up yet (a separate, already-documented gap), so this card cannot
/// show ✅/❌/🔥 the way [_PredictionCard] can once its round is scored.
class _FixturePredictionCard extends StatelessWidget {
  const _FixturePredictionCard({required this.prediction});
  final FixturePredictionDto prediction;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
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
    final Widget crest = ClipOval(
      child: brand == null
          ? Container(
              width: _crestSize,
              height: _crestSize,
              color: tokens.surfaceHigh,
            )
          : Image.network(
              brand.logoUrl,
              width: _crestSize,
              height: _crestSize,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                width: _crestSize,
                height: _crestSize,
                color: brand.c1,
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      width: _crestSize,
                      height: _crestSize,
                      color: tokens.surfaceHigh,
                    ),
            ),
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
