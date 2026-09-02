/// The regular user's unified **current month** screen (Monthly
/// Competitions transition, `docs/project-context.md` §9) — every public
/// competition's current-month fixture in one flat, no-picker list. This is
/// the screen `AccountScreen`'s "المباريات" (`account.matches`) button opens
/// instead of the Round-based `MatchesFeedScreen`.
///
/// Reuses the existing per-fixture submit slice exactly as-is, unmodified:
///   * [fixturePredictionControllerProvider] / [FixtureSubmissionState] from
///     `fixture_prediction_controller.dart` / `fixture_prediction_submission.dart`
///     — the same controller the season-scoped `FixturePredictionScreen`
///     already uses, keyed by the same `(seasonId, fixtureId)` pair. Each
///     `CurrentMonthFixtureItemDto.fixture` already carries its own
///     `seasonId`, so this screen needs no separate season lookup.
///
/// Only the read is new: [currentMonthFixturesProvider]
/// (`GET /feed/current-month-fixtures`, `current_month_fixtures_providers.dart`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_motion.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_stroke.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/score_pill.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_registry.dart';
import '../history/fixture_scores_providers.dart';
import '../history/prediction_history_providers.dart';
import '../leaderboards/season_leaderboard_screen.dart';
import 'current_month_fixtures_providers.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_submission.dart';
import 'kickoff_countdown.dart';

/// The current-month fixtures screen.
class CurrentMonthFixturesScreen extends ConsumerWidget {
  /// Creates the current-month fixtures screen.
  const CurrentMonthFixturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(currentMonthFixturesProvider);
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          l10n.matchesTitle,
          key: const Key('currentMonthFixtures.title'),
        ),
      ),
      body: feed.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          key: Key('currentMonthFixtures.loading'),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => _CurrentMonthFixturesError(
          error: error,
          onRetry: () => ref.invalidate(currentMonthFixturesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              key: const Key('currentMonthFixtures.empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.matchesEmpty,
                  key: const Key('currentMonthFixtures.empty.message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('currentMonthFixtures.list'),
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                _CurrentMonthFixtureCard(item: items[index]),
          );
        },
      ),
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
class _CurrentMonthFixturesError extends StatelessWidget {
  const _CurrentMonthFixturesError({
    required this.error,
    required this.onRetry,
  });

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
      key: const Key('currentMonthFixtures.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('currentMonthFixtures.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textPrimary),
            ),
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('currentMonthFixtures.error.retry'),
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

/// One fixture's card: owning competition label, team crests/names, a
/// compact status slot, and — once expanded — a home/away score pair, a
/// "double" chip, and its own submit action. Entirely independent of every
/// other card on screen (`fixturePredictionControllerProvider` is a family
/// keyed per `(seasonId, fixtureId)`).
///
/// On a successful submit, invalidates [myFixturePredictionsProvider] so
/// this card's status slot (and every other card's, harmlessly re-fetched)
/// reflects the just-saved forecast immediately rather than waiting for the
/// next natural refresh of that read.
class _CurrentMonthFixtureCard extends ConsumerStatefulWidget {
  const _CurrentMonthFixtureCard({required this.item});

  final CurrentMonthFixtureItemDto item;

  @override
  ConsumerState<_CurrentMonthFixtureCard> createState() =>
      _CurrentMonthFixtureCardState();
}

class _CurrentMonthFixtureCardState
    extends ConsumerState<_CurrentMonthFixtureCard> {
  bool _expanded = false;
  int _homeGoals = 0;
  int _awayGoals = 0;
  bool _isDouble = false;
  bool _prefilledFromPrediction = false;

  SeasonFixtureCardDto get _fixture => widget.item.fixture;

  bool get _isLocked {
    final kickoff = _fixture.kickoffAt;
    if (kickoff == null) return false;
    final parsed = DateTime.tryParse(kickoff)?.toUtc();
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now().toUtc());
  }

  FixturePredictionKey get _key =>
      (seasonId: _fixture.seasonId, fixtureId: _fixture.fixtureId);

  /// The caller's own prediction for this fixture, if any — a linear scan
  /// over [myFixturePredictionsProvider]'s full history, matched by
  /// fixture id. Mirrors the identical scan
  /// `prediction_history_screen.dart`'s `_FixturePredictionCard` already
  /// does over a fixture's scores list; this is the same idiom applied to
  /// the predictions list instead, not a new pattern.
  FixturePredictionDto? _findMyPrediction(List<FixturePredictionDto>? all) {
    if (all == null) return null;
    for (final FixturePredictionDto p in all) {
      if (p.fixtureId == _fixture.fixtureId) return p;
    }
    return null;
  }

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  /// Quick-fill (spec: "1/X/2 اختصار تعبئة سريعة فقط") — sets both steppers
  /// at once. Sends nothing itself and changes no contract: the two
  /// steppers stay the only source of truth [_submit] reads from, so the
  /// caller can still hand-adjust either side afterwards to land on an
  /// exact scoreline (`exact_scoreline` vs `correct_outcome`).
  void _applyQuickFill(int home, int away) {
    setState(() {
      _homeGoals = home;
      _awayGoals = away;
    });
  }

  void _incrementHome() => setState(() => _homeGoals++);

  void _decrementHome() => setState(() {
    if (_homeGoals > 0) _homeGoals--;
  });

  void _incrementAway() => setState(() => _awayGoals++);

  void _decrementAway() => setState(() {
    if (_awayGoals > 0) _awayGoals--;
  });

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
    // after myFixturePredictionsProvider's next unrelated refresh.
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
    // comes from fixtureScoresProvider, matched by participantId exactly as
    // prediction_history_screen.dart already does. Either read still
    // loading, erroring, or simply not finding this fixture degrades to
    // "no badge yet" — never a broken card.
    final myPredictionsAsync = ref.watch(myFixturePredictionsProvider);
    final FixturePredictionDto? myPrediction = _findMyPrediction(
      myPredictionsAsync.value,
    );

    final AsyncValue<FixtureScoresDto>? scoresAsync = myPrediction == null
        ? null
        : ref.watch(
            fixtureScoresProvider(_fixture.seasonId, _fixture.fixtureId),
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
    final fixtureId = _fixture.fixtureId;

    return Container(
      key: Key('currentMonthFixtures.fixture.$fixtureId'),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brCard,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('currentMonthFixtures.toggle.$fixtureId'),
              borderRadius: AppRadius.brCard,
              onTap: _toggleExpanded,
              child: Tooltip(
                message: _expanded
                    ? l10n.fixtureCardCollapseTooltip
                    : l10n.fixtureCardExpandTooltip,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              widget.item.competitionName,
                              key: Key(
                                'currentMonthFixtures.competition.$fixtureId',
                              ),
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            key: Key(
                              'currentMonthFixtures.viewLeaderboard.$fixtureId',
                            ),
                            tooltip: l10n.viewLeaderboardTooltip,
                            icon: Icon(
                              Icons.leaderboard_outlined,
                              color: tokens.textSecondary,
                            ),
                            iconSize: AppSizes.iconSm,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SeasonLeaderboardScreen(
                                  seasonId: _fixture.seasonId,
                                  seasonLabel: widget.item.seasonLabel,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _TeamHeader(
                              name: _fixture.homeTeam,
                              alignEnd: false,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            child: _CenterStatus(
                              locked: locked,
                              kickoffAt: _fixture.kickoffAt,
                              myPrediction: myPrediction,
                              grade: myGrade,
                            ),
                          ),
                          Expanded(
                            child: _TeamHeader(
                              name: _fixture.awayTeam,
                              alignEnd: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Center(
                        child: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: AppMotion.fast,
                          child: Icon(
                            Icons.expand_more,
                            size: AppSizes.iconSm,
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: _buildExpandedPanel(
                l10n: l10n,
                tokens: tokens,
                enabled: enabled,
                inFlight: inFlight,
                myPrediction: myPrediction,
                grade: myGrade,
                points: myPoints,
                submission: submission,
                fixtureId: fixtureId,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: AppMotion.standard,
            sizeCurve: AppMotion.standardCurve,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPanel({
    required AppLocalizations l10n,
    required AppTokens tokens,
    required bool enabled,
    required bool inFlight,
    required FixturePredictionDto? myPrediction,
    required String? grade,
    required int? points,
    required FixtureSubmissionState submission,
    required String fixtureId,
  }) {
    final bool isGraded =
        grade == 'exact_scoreline' ||
        grade == 'correct_outcome' ||
        grade == 'incorrect';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (myPrediction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
                  tone: isGraded ? AppBadgeTone.neutral : AppBadgeTone.muted,
                  icon: isGraded ? null : Icons.hourglass_bottom,
                ),
                if (isGraded && points != null)
                  AppBadge(
                    label: l10n.pointsAbbreviated(points),
                    tone: grade == 'incorrect'
                        ? AppBadgeTone.muted
                        : AppBadgeTone.success,
                    icon: grade == 'exact_scoreline' ? Icons.star : null,
                  )
                else if (!isGraded)
                  AppBadge(
                    label: l10n.predictionPendingResultLabel,
                    tone: AppBadgeTone.muted,
                  ),
              ],
            ),
          ),
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
            Expanded(
              child: _ScoreStepper(
                value: _homeGoals,
                enabled: enabled,
                onIncrement: _incrementHome,
                onDecrement: _decrementHome,
                fixtureId: fixtureId,
                side: 'home',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('—', style: TextStyle(color: tokens.textSecondary)),
            ),
            Expanded(
              child: _ScoreStepper(
                value: _awayGoals,
                enabled: enabled,
                onIncrement: _incrementAway,
                onDecrement: _decrementAway,
                fixtureId: fixtureId,
                side: 'away',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            _DoubleChip(
              selected: _isDouble,
              enabled: enabled,
              onTap: () => setState(() => _isDouble = !_isDouble),
              fixtureId: fixtureId,
            ),
            const Spacer(),
            FilledButton(
              key: Key('currentMonthFixtures.submit.$fixtureId'),
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
            key: Key('currentMonthFixtures.success.$fixtureId'),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              l10n.fixturePredictionSavedMessage,
              style: TextStyle(color: tokens.primary, fontSize: 12),
            ),
          ),
        if (submission is FixtureSubmissionFailed)
          Padding(
            key: Key('currentMonthFixtures.failure.$fixtureId'),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              ErrorPresenter.message(submission.error),
              key: Key('currentMonthFixtures.failure.message.$fixtureId'),
              style: TextStyle(color: tokens.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// One side's crest + display name, used in the collapsed row. Team
/// identity resolution is delegated entirely to `team_registry.dart` (the
/// same lookup `prediction_history_screen.dart`'s `_TeamMini` already
/// uses) — this widget never talks to the network or guesses a crest
/// itself, and degrades to a plain tinted circle for an unrecognized name.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.name, required this.alignEnd});

  final String? name;
  final bool alignEnd;

  static const double _crestSize = AppSizes.iconLg;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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

/// The compact status slot between the two [_TeamHeader]s in the collapsed
/// row. Exactly one of four mutually exclusive views, most-specific first
/// (a scored grade always wins over a bare pending forecast, which always
/// wins over a lock, which always wins over the live countdown):
///
///   * graded    — [grade] is a real outcome (`exact_scoreline` /
///     `correct_outcome` / `incorrect`) — shows the caller's own forecast
///     plus a grade badge (✅/❌/🔥 — same mapping
///     `prediction_history_screen.dart`'s `_ScoreLine` already uses).
///   * predicted — [myPrediction] exists but isn't graded yet (`pending`,
///     or no score row at all) — shows the caller's own forecast.
///   * locked    — kickoff has passed and neither of the above applies.
///   * upcoming  — delegates to [KickoffCountdown].
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
           ScorePill(home: prediction.homeGoals, away: prediction.awayGoals),
          const SizedBox(height: 2),
          Text(_badge ?? '', style: const TextStyle(fontSize: 12)),
        ],
      );
    }
    if (prediction != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
           ScorePill(home: prediction.homeGoals, away: prediction.awayGoals),
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


/// The 1/X/2 quick-fill row (spec: "أزرار 1/X/2 (تعبئة)"). The highlighted
/// button is *derived* from [homeGoals]/[awayGoals] rather than tracked as
/// its own selection, so it can never disagree with what the steppers
/// below actually hold.
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
            key: Key('currentMonthFixtures.quickFill1.$fixtureId'),
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
            key: Key('currentMonthFixtures.quickFillX.$fixtureId'),
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
            key: Key('currentMonthFixtures.quickFill2.$fixtureId'),
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

/// One 1/X/2 button. Touch target is exactly [AppSizes.minTouchTarget]
/// tall; selection is shown via a tinted fill + colored border + bold text
/// together (never color alone), matching `AppBadge`'s tone-pair
/// convention (tint background, solid foreground) rather than a solid
/// fill.
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

/// A numeric stepper for one side's predicted goals (spec: "Stepper رقمي
/// (بدل TextField خام)"). Refuses to go below zero locally — purely so the
/// decrement button can't produce a value the domain never accepts in the
/// first place ([FixturePredictionCommandDto.homeGoals]/[awayGoals] are
/// plain non-negative ints; the server remains the sole validator, Axiom 2).
class _ScoreStepper extends StatelessWidget {
  const _ScoreStepper({
    required this.value,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
    required this.fixtureId,
    required this.side,
  });

  final int value;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String fixtureId;
  final String side;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _StepperButton(
          key: Key('currentMonthFixtures.$side.decrement.$fixtureId'),
          icon: Icons.remove,
          tooltip: l10n.scoreStepperDecreaseTooltip,
          onTap: enabled && value > 0 ? onDecrement : null,
        ),
        SizedBox(
          width: AppSizes.minTouchTarget,
          child: Text(
            '$value',
            key: Key('currentMonthFixtures.$side.value.$fixtureId'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ),
        _StepperButton(
          key: Key('currentMonthFixtures.$side.increment.$fixtureId'),
          icon: Icons.add,
          tooltip: l10n.scoreStepperIncreaseTooltip,
          onTap: enabled ? onIncrement : null,
        ),
      ],
    );
  }
}

/// One +/- control, sized to [AppSizes.minTouchTarget] on both axes
/// (spec: "Touch targets ≥44dp").
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: AppSizes.iconMd,
      color: tokens.textPrimary,
      disabledColor: tokens.textMuted,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget,
      ),
    );
  }
}

/// The "double" toggle (spec: 'شريحة "×2 الدبل"' — replaces the old bare
/// [Checkbox]). Wraps the existing [AppBadge] component (its `gold`/`muted`
/// tones already give a tint+foreground pair, not color alone) instead of
/// inventing a new pill — this is purely presentational: it still just
/// flips the same `bool` [fixturePredictionControllerProvider]'s `isDouble`
/// parameter already took.
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
          key: Key('currentMonthFixtures.double.$fixtureId'),
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
