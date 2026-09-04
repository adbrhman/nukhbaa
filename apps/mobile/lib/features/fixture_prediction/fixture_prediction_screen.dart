/// The per-fixture prediction screen (Axiom 4 Amendment) — browses a
/// season's linked fixtures ([seasonFixturesProvider]) and lets the caller
/// submit an independent prediction for each one, one fixture at a time
/// (no round-wide batch — see fixture_prediction_controller.dart's class
/// doc).
///
/// Card design is intentionally kept at parity with
/// CurrentMonthFixturesScreen's _CurrentMonthFixtureCard (crests, 1/X/2
/// outcome buttons, "double" chip, live kickoff countdown, always-visible
/// submit — no expand/collapse step, no numeric score input) for visual
/// consistency between the two entry points onto the same underlying submit
/// slice ([fixturePredictionControllerProvider]/FixtureSubmissionState,
/// keyed by the same (seasonId, fixtureId) pair). The shared private
/// widgets are duplicated here rather than imported from that screen —
/// matching this codebase's existing convention of keeping each feature
/// file self-contained — not a new pattern.
///
/// Pre-fill from an already-submitted prediction and the "your forecast"
/// badge/grade reuse the exact same reads CurrentMonthFixturesScreen
/// already uses — a linear scan over [myFixturePredictionsProvider]'s
/// full history matched by fixture id, then (only if a prediction was
/// found) [fixtureScoresProvider] matched by participant id for the
/// grade/points. No new endpoint, no new provider — see this file's
/// `_findMyPrediction` doc.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_stroke.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/team_logo.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_identity.dart';
import '../competition/teams_providers.dart';
import '../history/fixture_scores_providers.dart';
import '../history/prediction_history_providers.dart';
import '../leaderboards/season_leaderboard_screen.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_providers.dart';
import 'fixture_prediction_submission.dart';
import 'kickoff_countdown.dart';

/// The fixture-list/predict screen for a single season.
class FixturePredictionScreen extends ConsumerWidget {
  /// Creates the fixture prediction screen for [seasonId].
  const FixturePredictionScreen({
    required this.seasonId,
    required this.seasonLabel,
    super.key,
  });

  /// The season whose linked fixtures are browsed and predicted.
  final String seasonId;

  /// The season's display label (for the leaderboard app-bar action).
  final String seasonLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fixtures = ref.watch(seasonFixturesProvider(seasonId));
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          l10n.fixturePredictionTitle,
          key: const Key('fixturePrediction.title'),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('fixturePrediction.viewLeaderboard'),
            tooltip: l10n.viewLeaderboardTooltip,
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SeasonLeaderboardScreen(
                  seasonId: seasonId,
                  seasonLabel: seasonLabel,
                ),
              ),
            ),
          ),
        ],
      ),
      body: fixtures.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _FixturePredictionError(
          error: error,
          onRetry: () => ref.invalidate(seasonFixturesProvider(seasonId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              key: const Key('fixturePrediction.empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.fixturePredictionEmptyMessage,
                  key: const Key('fixturePrediction.empty.message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('fixturePrediction.list'),
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) => _FixturePredictionCard(
              seasonId: seasonId,
              fixture: list[index],
            ),
          );
        },
      ),
    );
  }
}

/// Renders a thrown [AppError] via ErrorPresenter with a retry affordance.
class _FixturePredictionError extends StatelessWidget {
  const _FixturePredictionError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  AppError get _appError => error is AppError
      ? error as AppError
      : const AppError.transient(
          'client.unexpected',
          'Something went wrong. Please try again.',
        );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appError = _appError;
    final tokens = context.tokens;
    return Center(
      key: const Key('fixturePrediction.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('fixturePrediction.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textPrimary),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('fixturePrediction.error.retry'),
                onPressed: onRetry,
                child: Text(l10n.tryAgainButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One fixture's own editable card: crests + team names, a compact center
/// status slot, and — always visible when the fixture isn't locked — the
/// 1/X/2 outcome buttons, a "double" chip, and its own submit button. No
/// expand/collapse step: the submit affordance must always be reachable
/// without a hidden gesture. This fixture's submit lifecycle is entirely
/// independent of every other card on screen
/// (fixturePredictionControllerProvider is a family keyed per fixture).
///
/// Only the *outcome* (home win / draw / away win) is collected — not an
/// exact scoreline — via [_applyQuickFill], which still writes a concrete
/// `(1,0)`/`(0,0)`/`(0,1)` pair so the existing submit contract needs no
/// change.
class _FixturePredictionCard extends ConsumerStatefulWidget {
  const _FixturePredictionCard({required this.seasonId, required this.fixture});

  final String seasonId;
  final SeasonFixtureCardDto fixture;

  @override
  ConsumerState<_FixturePredictionCard> createState() =>
      _FixturePredictionCardState();
}

class _FixturePredictionCardState
    extends ConsumerState<_FixturePredictionCard> {
  int _homeGoals = 0;
  int _awayGoals = 0;
  bool _isDouble = false;
  bool _prefilledFromPrediction = false;

  bool get _isLocked {
    final kickoff = widget.fixture.kickoffAt;
    if (kickoff == null) return false;
    final parsed = DateTime.tryParse(kickoff)?.toUtc();
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now().toUtc());
  }

  FixturePredictionKey get _key =>
      (seasonId: widget.seasonId, fixtureId: widget.fixture.fixtureId);

  /// The caller's own prediction for this fixture, if any — a linear scan
  /// over [myFixturePredictionsProvider]'s full history, matched by
  /// fixture id. Identical idiom to
  /// current_month_fixtures_screen.dart's _CurrentMonthFixtureCardState
  /// (same doc there), duplicated per this file's self-contained-feature
  /// convention rather than shared.
  FixturePredictionDto? _findMyPrediction(List<FixturePredictionDto>? all) {
    if (all == null) return null;
    for (final FixturePredictionDto p in all) {
      if (p.fixtureId == widget.fixture.fixtureId) return p;
    }
    return null;
  }

  /// The only way to set an outcome (spec: "أزرار الاختيار 1/X/2 فقط، بلا
  /// مربعات نتيجة رقمية") — still writes a concrete goal pair so the
  /// existing submit contract needs no change.
  void _applyQuickFill(int home, int away) {
    setState(() {
      _homeGoals = home;
      _awayGoals = away;
    });
  }

  void _toggleDouble() => setState(() => _isDouble = !_isDouble);

  void _submit() {
    ref
        .read(fixturePredictionControllerProvider(_key).notifier)
        .submit(
          homeGoals: _homeGoals,
          awayGoals: _awayGoals,
          isDouble: _isDouble,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final submission = ref.watch(fixturePredictionControllerProvider(_key));

    // Keep "your forecast" status fresh right after a successful submit —
    // without this, the badge below would only reflect the new prediction
    // after myFixturePredictionsProvider's next unrelated refresh. Same
    // fix as current_month_fixtures_screen.dart's identical ref.listen.
    ref.listen<FixtureSubmissionState>(
      fixturePredictionControllerProvider(_key),
      (previous, next) {
        if (next is FixtureSubmissionSucceeded) {
          ref.invalidate(myFixturePredictionsProvider);
        }
      },
    );

    final inFlight = submission is FixtureSubmissionInFlight;
    final locked = _isLocked;

    // Reuse-only reads (no new architecture): "تم التوقع" comes from
    // matching this fixture in myFixturePredictionsProvider; "نتيجة/شارة"
    // comes from fixtureScoresProvider, matched by participantId — exactly
    // as current_month_fixtures_screen.dart already does.
    final myPredictionsAsync = ref.watch(myFixturePredictionsProvider);
    final FixturePredictionDto? myPrediction = _findMyPrediction(
      myPredictionsAsync.value,
    );

    final AsyncValue<FixtureScoresDto>? scoresAsync = myPrediction == null
        ? null
        : ref.watch(
            fixtureScoresProvider(widget.seasonId, widget.fixture.fixtureId),
          );
    String? myGrade;
    int? myPoints;
    if (myPrediction != null) {
      for (final ParticipantFixtureScoreDto s
          in scoresAsync?.value?.scores ?? const []) {
        if (s.participantId == myPrediction.participantId) {
          myGrade = s.grade;
          myPoints = s.points;
          break;
        }
      }
    }

    // One-time prefill from an existing prediction — guarded so it never
    // clobbers an edit already in progress once the async read resolves.
    if (!_prefilledFromPrediction && myPrediction != null) {
      _homeGoals = myPrediction.homeGoals;
      _awayGoals = myPrediction.awayGoals;
      _isDouble = myPrediction.isDouble;
      _prefilledFromPrediction = true;
    }

    final enabled = !inFlight && !locked;
    final fixtureId = widget.fixture.fixtureId;
    final bool isGraded =
        myGrade == 'exact_scoreline' ||
        myGrade == 'correct_outcome' ||
        myGrade == 'incorrect';

    return Container(
      key: Key('fixturePrediction.fixture.$fixtureId'),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brCard,
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _TeamHeader(
                    name: widget.fixture.homeTeam,
                    teamId: widget.fixture.homeTeamId,
                    alignEnd: false,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: _CenterStatus(
                    locked: locked,
                    kickoffAt: widget.fixture.kickoffAt,
                    myPrediction: myPrediction,
                    grade: myGrade,
                  ),
                ),
                Expanded(
                  child: _TeamHeader(
                    name: widget.fixture.awayTeam,
                    teamId: widget.fixture.awayTeamId,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
            if (myPrediction != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    AppBadge(
                      label: l10n.predictionYourForecastScoreLine(
                        myPrediction.homeGoals,
                        myPrediction.awayGoals,
                      ),
                      tone: isGraded
                          ? AppBadgeTone.neutral
                          : AppBadgeTone.muted,
                      icon: isGraded ? null : Icons.hourglass_bottom,
                    ),
                    if (isGraded && myPoints != null)
                      AppBadge(
                        label: l10n.pointsAbbreviated(myPoints),
                        tone: myGrade == 'incorrect'
                            ? AppBadgeTone.muted
                            : AppBadgeTone.success,
                        icon: myGrade == 'exact_scoreline' ? Icons.star : null,
                      )
                    else if (!isGraded)
                      AppBadge(
                        label: l10n.predictionPendingResultLabel,
                        tone: AppBadgeTone.muted,
                      ),
                  ],
                ),
              ),
            if (!locked) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _QuickFillRow(
                homeGoals: _homeGoals,
                awayGoals: _awayGoals,
                enabled: enabled,
                onSelect: _applyQuickFill,
                fixtureId: fixtureId,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  _DoubleChip(
                    selected: _isDouble,
                    enabled: enabled,
                    onTap: _toggleDouble,
                    fixtureId: fixtureId,
                  ),
                  const Spacer(),
                  FilledButton(
                    key: Key('fixturePrediction.submit.$fixtureId'),
                    onPressed: enabled ? _submit : null,
                    child: inFlight
                        ? const SizedBox(
                            width: AppSizes.progressSm,
                            height: AppSizes.progressSm,
                            child: CircularProgressIndicator(
                              strokeWidth: AppSizes.progressStroke,
                            ),
                          )
                        : Text(l10n.submitFixturePredictionButton),
                  ),
                ],
              ),
              if (submission is FixtureSubmissionSucceeded)
                Padding(
                  key: Key('fixturePrediction.success.$fixtureId'),
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    l10n.fixturePredictionSavedMessage,
                    style: TextStyle(color: tokens.primary, fontSize: 12),
                  ),
                ),
              if (submission is FixtureSubmissionFailed)
                Padding(
                  key: Key('fixturePrediction.failure.$fixtureId'),
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    ErrorPresenter.message(submission.error),
                    key: Key('fixturePrediction.failure.message.$fixtureId'),
                    style: TextStyle(color: tokens.error, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One side's crest + display name. Duplicated from
/// current_month_fixtures_screen.dart's _TeamHeader (same
/// self-contained-feature-file convention — see this file's doc), including
/// its [resolveTeamIdentity] resolution (model-backed team catalog first,
/// name-based `team_registry.dart` fallback otherwise).
class _TeamHeader extends ConsumerWidget {
  const _TeamHeader({
    required this.name,
    required this.teamId,
    required this.alignEnd,
  });

  final String? name;
  final String? teamId;
  final bool alignEnd;

  static const double _crestSize = AppSizes.iconLg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final catalog = ref.watch(teamCatalogProvider).value;
    final ResolvedTeamIdentity identity = resolveTeamIdentity(
      catalog: catalog,
      teamId: teamId,
      teamName: name,
    );
    final String display = identity.displayName;
    final Widget crest = TeamLogo(
      displayName: display,
      crestUrl: identity.crestUrl,
      brandColor: identity.brandColor,
      size: _crestSize,
    );
    final Text label = Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: TextStyle(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
    final List<Widget> children = alignEnd
        ? <Widget>[
            Expanded(child: label),
            const SizedBox(width: AppSpacing.xs),
            crest,
          ]
        : <Widget>[
            crest,
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: label),
          ];
    return Row(children: children);
  }
}

/// The compact status slot between the two [_TeamHeader]s. Duplicated from
/// current_month_fixtures_screen.dart's _CenterStatus with the same
/// four-branch precedence (graded > predicted > locked > upcoming).
/// [myPrediction]/[grade] are fed from the same
/// myFixturePredictionsProvider/fixtureScoresProvider reads as that screen
/// (see _FixturePredictionCardState.build), so all four branches are
/// reachable here too.
class _CenterStatus extends StatelessWidget {
  const _CenterStatus({
    required this.locked,
    required this.kickoffAt,
    required this.myPrediction,
    required this.grade,
  });

  final bool locked;
  final String? kickoffAt;
  final FixturePredictionDto? myPrediction;
  final String? grade;

  bool get _isGraded =>
      grade == 'exact_scoreline' ||
      grade == 'correct_outcome' ||
      grade == 'incorrect';

  String? get _badge {
    switch (grade) {
      case 'exact_scoreline':
        return (myPrediction?.isDouble ?? false) ? '🔥' : '✅';
      case 'correct_outcome':
      case 'incorrect':
        return '❌';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final FixturePredictionDto? prediction = myPrediction;

    if (_isGraded && prediction != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ScorePill(home: prediction.homeGoals, away: prediction.awayGoals),
          const SizedBox(height: 2),
          Text(_badge ?? '', style: const TextStyle(fontSize: 12)),
        ],
      );
    }
    if (prediction != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ScorePill(home: prediction.homeGoals, away: prediction.awayGoals),
          const SizedBox(height: 2),
          Text(
            l10n.predictionPendingResultLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textMuted, fontSize: 10),
          ),
        ],
      );
    }
    if (locked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.lock_outline,
            size: AppSizes.iconSm,
            color: tokens.textMuted,
          ),
          const SizedBox(height: 2),
          Text(
            l10n.predictionFixtureLockedLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.textMuted, fontSize: 10),
          ),
        ],
      );
    }
    return KickoffCountdown(kickoffAt: kickoffAt);
  }
}

/// The centered "H - A" pill. Duplicated from
/// current_month_fixtures_screen.dart's equivalent (same
/// self-contained-feature-file convention).
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.home, required this.away});

  final int home;
  final int away;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brSm,
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

/// The 1/X/2 outcome row (spec: "أزرار الاختيار 1/X/2 فقط") — the only way
/// to set a prediction now. Duplicated from
/// current_month_fixtures_screen.dart's _QuickFillRow — the highlighted
/// button is derived from [homeGoals]/[awayGoals], never tracked as its
/// own selection.
class _QuickFillRow extends StatelessWidget {
  const _QuickFillRow({
    required this.homeGoals,
    required this.awayGoals,
    required this.enabled,
    required this.onSelect,
    required this.fixtureId,
  });

  final int homeGoals;
  final int awayGoals;
  final bool enabled;
  final void Function(int home, int away) onSelect;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isHomeWin = homeGoals > awayGoals;
    final bool isDraw = homeGoals == awayGoals;
    final bool isAwayWin = homeGoals < awayGoals;
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuickFillButton(
            key: Key('fixturePrediction.quickFill1.$fixtureId'),
            label: '1',
            tooltip: l10n.predictionQuickFillHomeWinTooltip,
            selected: isHomeWin,
            enabled: enabled,
            onTap: () => onSelect(1, 0),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickFillButton(
            key: Key('fixturePrediction.quickFillX.$fixtureId'),
            label: 'X',
            tooltip: l10n.predictionQuickFillDrawTooltip,
            selected: isDraw,
            enabled: enabled,
            onTap: () => onSelect(0, 0),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuickFillButton(
            key: Key('fixturePrediction.quickFill2.$fixtureId'),
            label: '2',
            tooltip: l10n.predictionQuickFillAwayWinTooltip,
            selected: isAwayWin,
            enabled: enabled,
            onTap: () => onSelect(0, 1),
          ),
        ),
      ],
    );
  }
}

/// One 1/X/2 button. Duplicated from
/// current_month_fixtures_screen.dart's _QuickFillButton.
class _QuickFillButton extends StatelessWidget {
  const _QuickFillButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Color fg = selected ? tokens.primary : tokens.textSecondary;
    final Color bg = selected
        ? tokens.primary.withValues(alpha: 0.14)
        : tokens.surfaceElevated;
    final Color border = selected ? tokens.primary : tokens.border;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          borderRadius: AppRadius.brButton,
          child: InkWell(
            borderRadius: AppRadius.brButton,
            onTap: enabled ? onTap : null,
            child: Container(
              height: AppSizes.minTouchTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: AppRadius.brButton,
                border: Border.all(
                  color: border,
                  width: selected ? AppStroke.selected : AppStroke.regular,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "double" toggle. Duplicated from
/// current_month_fixtures_screen.dart's _DoubleChip, wrapping the existing
/// [AppBadge] component instead of a bare [Checkbox]. The tap target spans
/// a fixed minimum width (not just the content's own width) so a near-miss
/// tap next to the badge still registers.
class _DoubleChip extends StatelessWidget {
  const _DoubleChip({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.fixtureId,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('fixturePrediction.double.$fixtureId'),
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
              minWidth: AppSizes.minTouchTarget,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: AppBadge(
              label: '×2 ${l10n.predictionDoubleLabel}',
              tone: selected ? AppBadgeTone.gold : AppBadgeTone.muted,
              icon: selected ? Icons.check_circle : Icons.circle_outlined,
            ),
          ),
        ),
      ),
    );
  }
}
