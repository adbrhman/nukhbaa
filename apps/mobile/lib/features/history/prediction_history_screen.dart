library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/format/timestamps.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/team_logo.dart';
import '../../core/ui/score_pill.dart';
import '../../core/ui/app_badge.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_identity.dart';
import '../competition/widgets/async_list_view.dart';
import '../fixture_prediction/widgets/live_matches_chip.dart';
import 'fixture_scores_providers.dart';
import 'prediction_history_providers.dart';
import 'prediction_lookup_providers.dart';

/// The caller's own aggregated prediction history — every per-fixture
/// prediction they have ever submitted, across every fixture and season,
/// newest first. The retired round-scoped history (`GET /me/predictions`)
/// is no longer shown here (docs/project-context.md, "Legacy `Round`
/// predictions in `prediction_history_screen.dart`" — the app has not
/// launched yet, so there was no external history to preserve).
///
/// Each card shows the fixture's kickoff, the forecast scoreline, when it
/// was submitted, and one labelled status: the server's verdict and points
/// once [fixtureScoresProvider] resolves a grade, otherwise where the
/// fixture stands against its kickoff (not started / live / awaiting).
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
      // The shell's bottom bar floats over the page (`extendBody`), so the
      // list must stop above it -- the same SafeArea the other tabs use.
      body: SafeArea(
        top: false,
        child: AsyncListView<FixturePredictionDto>(
          value: history,
          emptyMessage: l10n.predictionHistoryEmpty,
          onRetry: () => ref.invalidate(myFixturePredictionsProvider),
          itemBuilder: (context, prediction) =>
              _FixturePredictionCard(prediction: prediction),
        ),
      ),
    );
  }
}

/// A single historical per-fixture forecast (Axiom 4 Amendment).
///
/// Team names and the kickoff come from [currentMonthFixturesByIdProvider]
/// -- an index over the same feed the fixtures screen renders -- because
/// [FixturePredictionDto.seasonId] is the *participant's* season, not the
/// fixture's, and a monthly competition gathers its fixtures from several
/// leagues. A still-loading read, or a fixture outside the current month,
/// falls back to the raw fixture id and no kickoff line rather than a
/// broken card.
///
/// Kickoff and submission are two separate, labelled lines: the card used
/// to show only the submission instant at the top, where it read like the
/// match time. The verdict and points come from [fixtureScoresProvider]
/// (server-computed; the client derives no point). A `null` seasonId, a
/// still-loading read, or any read error all degrade the same way: no
/// verdict, only the kickoff-relative status.
class _FixturePredictionCard extends ConsumerWidget {
  const _FixturePredictionCard({required this.prediction});
  final FixturePredictionDto prediction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? seasonId = prediction.seasonId;
    final AsyncValue<FixtureScoresDto>? scoresAsync = seasonId == null
        ? null
        : ref.watch(fixtureScoresProvider(seasonId, prediction.fixtureId));
    String? grade;
    int? points;
    for (final ParticipantFixtureScoreDto s
        in scoresAsync?.value?.scores ?? const []) {
      if (s.participantId == prediction.participantId) {
        grade = s.grade;
        points = s.points;
        break;
      }
    }

    // Team names come from the current-month feed, not from the
    // prediction's own season: `seasonId` is derived server-side from the
    // *participant's* season, which is not where the fixtures live once a
    // monthly competition gathers fixtures from several leagues.
    final AsyncValue<Map<String, SeasonFixtureCardDto>> fixturesById = ref
        .watch(currentMonthFixturesByIdProvider);
    final SeasonFixtureCardDto? fixture =
        fixturesById.value?[prediction.fixtureId];
    final String? kickoffAt = fixture?.kickoffAt;
    final AppBadge? status = _statusBadge(
      l10n,
      grade: grade,
      points: points,
      kickoffAt: kickoffAt,
    );
    final TextStyle? metaStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary);

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
            if (kickoffAt != null) ...<Widget>[
              Text(
                l10n.historyKickoffAt(formatDayAndTime(context, kickoffAt)),
                key: Key('history.kickoffAt.${prediction.id}'),
                style: metaStyle?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
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
                fixture: fixture,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l10n.historySubmittedAt(
                    formatDayAndTime(context, prediction.submittedAt),
                  ),
                  key: Key('history.submittedAt.${prediction.id}'),
                  style: metaStyle,
                ),
                if (status != null) status,
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The card's single status, most specific first: the server's verdict
  /// with its own points once graded; otherwise where the fixture stands
  /// against its kickoff. "Live" is the same time estimate the matches
  /// screen uses ([isFixtureLive]) -- the feed carries no status field.
  /// `null` when neither a grade nor a kickoff is known.
  static AppBadge? _statusBadge(
    AppLocalizations l10n, {
    required String? grade,
    required int? points,
    required String? kickoffAt,
  }) {
    final String? pointsText = points == null
        ? null
        : l10n.pointsAbbreviated(points);
    String withPoints(String label) =>
        pointsText == null ? label : '$label · $pointsText';
    switch (grade) {
      case 'exact_scoreline':
        return AppBadge(
          label: withPoints(l10n.historyGradeExact),
          tone: AppBadgeTone.success,
          icon: Icons.check_circle_rounded,
        );
      case 'correct_outcome':
        return AppBadge(
          label: withPoints(l10n.historyGradeOutcome),
          tone: (points ?? 0) > 0 ? AppBadgeTone.success : AppBadgeTone.muted,
        );
      case 'incorrect':
        return AppBadge(
          label: withPoints(l10n.historyGradeWrong),
          tone: AppBadgeTone.danger,
          icon: Icons.cancel_rounded,
        );
      case 'missed':
        return AppBadge(
          label: l10n.historyGradeMissed,
          tone: AppBadgeTone.muted,
        );
    }
    final DateTime? kickoff = kickoffAt == null
        ? null
        : DateTime.tryParse(kickoffAt)?.toUtc();
    if (kickoff == null) return null;
    if (DateTime.now().toUtc().isBefore(kickoff)) {
      return AppBadge(
        label: l10n.historyStatusUpcoming,
        icon: Icons.schedule_rounded,
      );
    }
    if (isFixtureLive(kickoffAt)) {
      return AppBadge(
        label: l10n.fixturesLiveLabel,
        tone: AppBadgeTone.danger,
        icon: Icons.circle,
      );
    }
    return AppBadge(
      label: l10n.predictionPendingResultLabel,
      tone: AppBadgeTone.muted,
      icon: Icons.lock_outline,
    );
  }
}

/// One fixture's scoreline: "[crest] Home  2 - 1  Away [crest]", with a
/// small "double" badge under the pill when this was the day's double.
/// Falls back to the raw fixture id (no crests) when [fixture] is `null` --
/// the resolved read hasn't returned this fixture yet, or it is no longer
/// linked to the season. The verdict no longer sits here as a bare glyph
/// (it rendered as an unexplained "x"); it is the card's labelled status.
class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.score, required this.fixture, super.key});

  final FixtureScoreDto score;
  final SeasonFixtureCardDto? fixture;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SeasonFixtureCardDto? f = fixture;
    final bool hasNames =
        (f?.homeTeam?.isNotEmpty ?? false) &&
        (f?.awayTeam?.isNotEmpty ?? false);

    if (!hasNames) {
      return Text(
        l10n.predictionHistoryScoreLine(
          score.fixtureId,
          score.homeGoals,
          score.awayGoals,
        ),
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
              ScorePill(home: score.homeGoals, away: score.awayGoals),
              if (score.isDouble)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AppBadge(
                    label: l10n.predictionDoubleLabel,
                    tone: AppBadgeTone.gold,
                    icon: Icons.bolt_rounded,
                  ),
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
    // No catalog here: the score line resolves by name, which is what the
    // season fixture list carries. The name-only branch still yields the
    // bundled asset path and brand colour.
    final ResolvedTeamIdentity identity = resolveTeamIdentity(
      catalog: null,
      teamName: name,
    );
    final String display = identity.displayName;
    final Widget crest = TeamLogo(
      displayName: display,
      crestUrl: identity.crestUrl,
      assetPath: identity.assetPath,
      brandColor: identity.brandColor,
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
