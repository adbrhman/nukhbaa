/// A modal bottom sheet for submitting/editing one fixture's prediction —
/// opened from `MatchCard`'s `onTap`/`onPredictTap` on
/// `CurrentMonthFixturesScreen` (Elite Obsidian card wiring). Carries
/// exactly the interaction the former inline-expanding
/// `_CurrentMonthFixtureCard` had (1/X/2 quick-fill, numeric steppers, the
/// "double" chip, submit) against the same
/// `fixturePredictionControllerProvider`/`FixtureSubmissionState` slice,
/// keyed by the same `(seasonId, fixtureId)` pair — just presented as a
/// sheet instead of an inline expand.
///
/// Self-contained per this codebase's existing convention
/// (`fixture_prediction_screen.dart`'s file doc): the quick-fill/stepper/
/// double-chip widgets are duplicated here, not imported from
/// `current_month_fixtures_screen.dart` (they are private there anyway).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_stroke.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_badge.dart';
import '../../l10n/app_localizations.dart';
import '../competition/team_registry.dart';
import '../history/fixture_scores_providers.dart';
import '../history/prediction_history_providers.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_submission.dart';

/// Opens the predict sheet for [item].
Future<void> showFixturePredictSheet({
  required BuildContext context,
  required CurrentMonthFixtureItemDto item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FixturePredictSheet(item: item),
  );
}

class _FixturePredictSheet extends ConsumerStatefulWidget {
  const _FixturePredictSheet({required this.item});

  final CurrentMonthFixtureItemDto item;

  @override
  ConsumerState<_FixturePredictSheet> createState() =>
      _FixturePredictSheetState();
}

class _FixturePredictSheetState extends ConsumerState<_FixturePredictSheet> {
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

  /// Mirrors `_CurrentMonthFixtureCardState._findMyPrediction`: a linear
  /// scan over the caller's full prediction history, matched by fixture id.
  FixturePredictionDto? _findMyPrediction(List<FixturePredictionDto>? all) {
    if (all == null) return null;
    for (final FixturePredictionDto p in all) {
      if (p.fixtureId == _fixture.fixtureId) return p;
    }
    return null;
  }

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
    // same reasoning as the former inline card.
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

    if (!_prefilledFromPrediction && myPrediction != null) {
      _homeGoals = myPrediction.homeGoals;
      _awayGoals = myPrediction.awayGoals;
      _isDouble = myPrediction.isDouble;
      _prefilledFromPrediction = true;
    }

    final enabled = !inFlight && !locked;
    final fixtureId = _fixture.fixtureId;
    final bool isGraded =
        myGrade == 'exact_scoreline' ||
        myGrade == 'correct_outcome' ||
        myGrade == 'incorrect';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          key: Key('fixturePredictSheet.$fixtureId'),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            border: Border.all(color: tokens.border),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                l10n.fixtureVsTitle(
                  teamDisplayName(_fixture.homeTeam),
                  teamDisplayName(_fixture.awayTeam),
                ),
                key: Key('fixturePredictSheet.title.$fixtureId'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (myPrediction != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Wrap(
                    alignment: WrapAlignment.center,
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
                          icon: myGrade == 'exact_scoreline'
                              ? Icons.star
                              : null,
                        )
                      else if (!isGraded)
                        AppBadge(
                          label: l10n.predictionPendingResultLabel,
                          tone: AppBadgeTone.muted,
                        ),
                    ],
                  ),
                ),
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppBadge(
                    label: l10n.predictionFixtureLockedLabel,
                    tone: AppBadgeTone.muted,
                    icon: Icons.lock_outline,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text(
                      '—',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
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
                    key: Key('fixturePredictSheet.submit.$fixtureId'),
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
                  key: Key('fixturePredictSheet.success.$fixtureId'),
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    l10n.fixturePredictionSavedMessage,
                    style: TextStyle(color: tokens.primary, fontSize: 12),
                  ),
                ),
              if (submission is FixtureSubmissionFailed)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    ErrorPresenter.message(submission.error),
                    key: Key('fixturePredictSheet.failure.$fixtureId'),
                    style: TextStyle(color: tokens.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 1/X/2 quick-fill row — duplicated from
/// `current_month_fixtures_screen.dart`'s private `_QuickFillRow` (same
/// derivation-from-goals logic, same tooltips).
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
            key: Key('fixturePredictSheet.quickFill1.$fixtureId'),
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
            key: Key('fixturePredictSheet.quickFillX.$fixtureId'),
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
            key: Key('fixturePredictSheet.quickFill2.$fixtureId'),
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

/// One 1/X/2 button — duplicated verbatim from
/// `current_month_fixtures_screen.dart`'s private `_QuickFillButton`.
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

/// A numeric stepper for one side's predicted goals — duplicated verbatim
/// from `current_month_fixtures_screen.dart`'s private `_ScoreStepper`.
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
          key: Key('fixturePredictSheet.$side.decrement.$fixtureId'),
          icon: Icons.remove,
          tooltip: l10n.scoreStepperDecreaseTooltip,
          onTap: enabled && value > 0 ? onDecrement : null,
        ),
        SizedBox(
          width: AppSizes.minTouchTarget,
          child: Text(
            '$value',
            key: Key('fixturePredictSheet.$side.value.$fixtureId'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ),
        _StepperButton(
          key: Key('fixturePredictSheet.$side.increment.$fixtureId'),
          icon: Icons.add,
          tooltip: l10n.scoreStepperIncreaseTooltip,
          onTap: enabled ? onIncrement : null,
        ),
      ],
    );
  }
}

/// One +/- control — duplicated verbatim from
/// `current_month_fixtures_screen.dart`'s private `_StepperButton`.
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

/// The "double" toggle — duplicated verbatim from
/// `current_month_fixtures_screen.dart`'s private `_DoubleChip`.
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
          key: Key('fixturePredictSheet.double.$fixtureId'),
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
