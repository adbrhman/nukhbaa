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

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_stroke.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/team_logo.dart';
import '../../core/ui/score_pill.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_identity.dart';
import '../competition/teams_providers.dart';
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
      body: SafeArea(
        bottom: true,
        top: false,
        child: feed.when(
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
/// compact status slot, and — always visible when the fixture isn't locked
/// — the 1/X/2 outcome buttons, a "double" chip, and its own submit action.
/// No expand/collapse step: the submit affordance must always be reachable
/// without a hidden gesture. Entirely independent of every other card on
/// screen (`fixturePredictionControllerProvider` is a family keyed per
/// `(seasonId, fixtureId)`).
///
/// Only the *outcome* (home win / draw / away win) is collected — not an
/// exact scoreline — via [_applyQuickFill], which still writes a concrete
/// `(1,0)`/`(0,0)`/`(0,1)` pair so the existing submit contract
/// ([FixturePredictionCommandDto.homeGoals]/[awayGoals]) needs no change.
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
  int? _homeGoals;
  int? _awayGoals;
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

  /// The only way to set an outcome (spec: "أزرار الاختيار 1/X/2 فقط، بلا
  /// مربعات نتيجة رقمية") — still writes a concrete goal pair so the
  /// existing submit contract needs no change.
  void _applyQuickFill(int home, int away) {
    setState(() {
      _homeGoals = home;
      _awayGoals = away;
    });
  }

  void _toggleDouble() {
    setState(() => _isDouble = !_isDouble);
  }

  void _submit() {
    final int? home = _homeGoals;
    final int? away = _awayGoals;
    if (home == null || away == null) return;
    ref
        .read(fixturePredictionControllerProvider(_key).notifier)
        .submit(homeGoals: home, awayGoals: away, isDouble: _isDouble);
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
    final bool hasPick = _homeGoals != null && _awayGoals != null;
    final fixtureId = _fixture.fixtureId;
    final bool isGraded =
        myGrade == 'exact_scoreline' ||
        myGrade == 'correct_outcome' ||
        myGrade == 'incorrect';

    return Container(
      key: Key('currentMonthFixtures.fixture.$fixtureId'),
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
                  child: Text(
                    widget.item.competitionName,
                    key: Key('currentMonthFixtures.competition.$fixtureId'),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('currentMonthFixtures.viewLeaderboard.$fixtureId'),
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
                    teamId: _fixture.homeTeamId,
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
                    teamId: _fixture.awayTeamId,
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
                    key: Key('currentMonthFixtures.submit.$fixtureId'),
                    onPressed: enabled && hasPick ? _submit : null,
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
          ],
        ),
      ),
    );
  }
}

/// One side's crest + display name, used in the collapsed row. Resolves
/// through [resolveTeamIdentity]: the model-backed `football_data.teams`
/// catalog when this fixture carries a resolved [teamId], falling back to
/// `team_registry.dart`'s name-based lookup otherwise (the same lookup
/// `prediction_history_screen.dart`'s `_TeamMini` still uses for its
/// Round-based, id-less fixtures). Never talks to the network itself beyond
/// watching the already-shared [teamCatalogProvider], and degrades to a
/// plain tinted circle for an unrecognized/missing team.
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

/// The compact status slot between the two [_TeamHeader]s. Exactly one of
/// four mutually exclusive views, most-specific first (a scored grade
/// always wins over a bare pending forecast, which always wins over a
/// lock, which always wins over the live countdown):
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

/// The 1/X/2 outcome row (spec: "أزرار الاختيار 1/X/2 فقط") — the only way
/// to set a prediction now. The highlighted button is *derived* from
/// [homeGoals]/[awayGoals] rather than tracked as its own selection, so it
/// can never disagree with what was actually last selected.
class _QuickFillRow extends StatelessWidget {
  const _QuickFillRow({
    required this.homeGoals,
    required this.awayGoals,
    required this.enabled,
    required this.onSelect,
    required this.fixtureId,
  });

  final int? homeGoals;
  final int? awayGoals;
  final bool enabled;
  final void Function(int home, int away) onSelect;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final int? home = homeGoals;
    final int? away = awayGoals;
    final bool picked = home != null && away != null;
    final bool isHomeWin = picked && home > away;
    final bool isDraw = picked && home == away;
    final bool isAwayWin = picked && home < away;
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

/// The "double" toggle (spec: 'شريحة "×2 الدبل"'). Wraps the existing
/// [AppBadge] component (its `gold`/`muted` tones already give a
/// tint+foreground pair, not color alone) instead of inventing a new pill
/// — this is purely presentational: it still just flips the same `bool`
/// [fixturePredictionControllerProvider]'s `isDouble` parameter already
/// took. The tap target spans a fixed minimum width (not just the
/// content's own width) so a near-miss tap next to the badge still
/// registers.
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
    final tokens = context.tokens;
    final Color fg = selected ? tokens.gold : tokens.textSecondary;
    final Color bg = selected
        ? tokens.gold.withValues(alpha: 0.16)
        : tokens.surfaceElevated;
    final Color border = selected ? tokens.gold : tokens.border;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      // Plain GestureDetector with opaque hit-test behavior instead of
      // InkWell/Material — rules out any InkWell-specific hit-testing
      // quirk while debugging the reported "double chip doesn't respond"
      // issue; also gives the selected state an unmistakable
      // tint+border+bold treatment (matching _QuickFillButton's
      // convention) instead of relying on AppBadge's subtler tone swap.
      child: GestureDetector(
        key: Key('currentMonthFixtures.double.$fixtureId'),
        behavior: HitTestBehavior.opaque,
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
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            border: Border.all(
              color: border,
              width: selected ? AppStroke.selected : AppStroke.regular,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: AppSizes.iconInline,
                color: fg,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '×2 ${l10n.predictionDoubleLabel}',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
