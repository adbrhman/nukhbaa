/// The FotMob-style match card (`match-card-fotmob-spec.md`) — replaces
/// `current_month_fixtures_screen.dart`'s former `_CurrentMonthFixtureCard`
/// as the one card `CurrentMonthFixturesScreen` renders per fixture. Lives
/// under `features/fixture_prediction/widgets/` (not `core/ui/`) because it
/// needs [resolveTeamIdentity] + `teamCatalogProvider`, and `core/ui/**` may
/// never import `features/**` (`import_lint`).
///
/// Reuses the existing per-fixture submit slice exactly as-is, unmodified:
/// [fixturePredictionControllerProvider] / [FixtureSubmissionState] keyed by
/// `(seasonId, fixtureId)`, [myFixturePredictionsProvider],
/// [fixtureScoresProvider], [teamCatalogProvider] — no new provider, no new
/// endpoint, no new architecture. The card computes no point, rank, or
/// probability of its own (Axiom 2) — every number it shows is either the
/// user's own not-yet-submitted pick or a value already echoed back by the
/// server.
///
/// ## States (exclusive, most specific first — §6 of the spec)
/// 1. **Graded** — hide the steppers/double/submit; show the stored
///    forecast + a points badge in the middle slot.
/// 2. **Locked** (kickoff passed, not graded) — hide the steppers/double/
///    submit; show a lock icon + "Started" in the middle slot, regardless
///    of whether a prediction exists (a deliberate simplification over the
///    prior design: once locked, the point is moot until graded).
/// 3. **Predicted** (has a prediction, not locked, not graded) — the score
///    steppers stay active, pre-filled from the stored prediction, plus a
///    "pending result" badge under the body.
/// 4. **Open** (no prediction yet, not locked) — steppers start at `null`
///    ("?"), submit stays disabled until both sides have a value.
///
/// ## Explicit submit, not auto-save (§5 decision, recorded)
/// The reference FotMob design auto-saves without ever showing a submit
/// control. Nukhba's submission is an explicit command to the server
/// (`FixturePredictionController.submit`), so this card keeps a compact
/// submit button — the spec's own §5 flags this exact question as
/// "requires project-owner approval before turning into auto-save", and a
/// later block appended to the spec's acceptance-criteria section describes
/// an auto-save debounce mechanism that contradicts that explicit gate.
/// Per the spec's own delivery instructions (§11.7: record a deviation as a
/// decision with its reason, not as a pending question), the decision taken
/// here is: implement the explicit-submit design §5 itself asks for and
/// that acceptance criterion §6-row-4 ("submit disabled until two numbers
/// entered") already assumes — and do NOT implement the contradicting
/// auto-save block, since that would be exactly the unapproved change §5
/// warns against.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl is already a transitive dependency (pulled in by the SDK's
// flutter_localizations, the same package the generated l10n files import
// it from — see their own `// ignore_for_file: type=lint`); not declared
// directly in pubspec.yaml, and the task's "no new dependencies" rule
// means it should not be added there just to silence this lint.
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_motion.dart';
import '../../../core/design/app_opacity.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_stroke.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/ui/app_badge.dart';
import '../../../core/ui/score_pill.dart';
import '../../../core/ui/team_logo.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/competition_logo_assets.dart';
import '../../competition/team_identity.dart';
import '../../competition/teams_providers.dart';
import '../../history/fixture_scores_providers.dart';
import '../../history/prediction_history_providers.dart';
import '../../leaderboards/season_leaderboard_screen.dart';
import '../fixture_prediction_controller.dart';
import '../fixture_prediction_submission.dart';

/// One fixture's FotMob-style card. Entirely independent of every other
/// card on screen (`fixturePredictionControllerProvider` is a family keyed
/// per `(seasonId, fixtureId)`).
class FotmobMatchCard extends ConsumerStatefulWidget {
  /// Creates the card for [item].
  const FotmobMatchCard({required this.item, super.key});

  /// The current-month feed item this card renders.
  final CurrentMonthFixtureItemDto item;

  @override
  ConsumerState<FotmobMatchCard> createState() => _FotmobMatchCardState();
}

class _FotmobMatchCardState extends ConsumerState<FotmobMatchCard> {
  // Nullable — a card must never show an auto-selected outcome the user
  // never picked (fixed in commit c70b8b1; do not reinitialize to 0).
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
  /// fixture id (unchanged read, same idiom used across every fixture
  /// card in this app).
  FixturePredictionDto? _findMyPrediction(List<FixturePredictionDto>? all) {
    if (all == null) return null;
    for (final FixturePredictionDto p in all) {
      if (p.fixtureId == _fixture.fixtureId) return p;
    }
    return null;
  }

  void _incrementHome() =>
      setState(() => _homeGoals = ((_homeGoals ?? -1) + 1).clamp(0, 99));

  void _decrementHome() {
    final int? value = _homeGoals;
    if (value == null || value <= 0) return;
    setState(() => _homeGoals = value - 1);
  }

  void _incrementAway() =>
      setState(() => _awayGoals = ((_awayGoals ?? -1) + 1).clamp(0, 99));

  void _decrementAway() {
    final int? value = _awayGoals;
    if (value == null || value <= 0) return;
    setState(() => _awayGoals = value - 1);
  }

  void _toggleDouble() => setState(() => _isDouble = !_isDouble);

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
    final bool isGraded =
        myGrade == 'exact_scoreline' ||
        myGrade == 'correct_outcome' ||
        myGrade == 'incorrect';

    // One-time prefill from an existing prediction — guarded so it never
    // clobbers an edit already in progress once the async read resolves.
    if (!_prefilledFromPrediction && myPrediction != null) {
      _homeGoals = myPrediction.homeGoals;
      _awayGoals = myPrediction.awayGoals;
      _isDouble = myPrediction.isDouble;
      _prefilledFromPrediction = true;
    }

    final bool showEditableControls = !locked && !isGraded;
    final bool enabled = !inFlight && !locked;
    final bool hasPick = _homeGoals != null && _awayGoals != null;
    final bool showPendingBadge = !locked && !isGraded && myPrediction != null;
    final String fixtureId = _fixture.fixtureId;

    final catalog = ref.watch(teamCatalogProvider).value;
    final ResolvedTeamIdentity home = resolveTeamIdentity(
      catalog: catalog,
      teamId: _fixture.homeTeamId,
      teamName: _fixture.homeTeam,
    );
    final ResolvedTeamIdentity away = resolveTeamIdentity(
      catalog: catalog,
      teamId: _fixture.awayTeamId,
      teamName: _fixture.awayTeam,
    );
    final Color homeBase = home.brandColor ?? tokens.surfaceElevated;
    final Color awayBase = away.brandColor ?? tokens.surfaceElevated;
    final Color glowColor = Color.lerp(
      homeBase,
      awayBase,
      0.5,
    )!.withValues(alpha: AppOpacity.glow);

    return Container(
      key: Key('currentMonthFixtures.fixture.$fixtureId'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: tokens.border, width: AppStroke.regular),
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          stops: const <double>[0.0, 0.5, 1.0],
          colors: <Color>[
            homeBase.withValues(alpha: AppOpacity.tint),
            tokens.surface,
            awayBase.withValues(alpha: AppOpacity.tint),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _CardHeader(
              competitionId: widget.item.competitionId,
              competitionName: widget.item.competitionName,
              kickoffAt: _fixture.kickoffAt,
              onOpenLeaderboard: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SeasonLeaderboardScreen(
                    seasonId: _fixture.seasonId,
                    seasonLabel: widget.item.seasonLabel,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: _TeamColumn(
                    displayName: home.displayName,
                    crestUrl: home.crestUrl,
                    brandColor: home.brandColor,
                  ),
                ),
                _MiddleSlot(
                  isGraded: isGraded,
                  locked: locked,
                  myPrediction: myPrediction,
                  grade: myGrade,
                  points: myPoints,
                  homeGoals: _homeGoals,
                  awayGoals: _awayGoals,
                  enabled: enabled,
                  showEditableControls: showEditableControls,
                  fixtureId: fixtureId,
                  onIncrementHome: _incrementHome,
                  onDecrementHome: _decrementHome,
                  onIncrementAway: _incrementAway,
                  onDecrementAway: _decrementAway,
                ),
                Expanded(
                  child: _TeamColumn(
                    displayName: away.displayName,
                    crestUrl: away.crestUrl,
                    brandColor: away.brandColor,
                  ),
                ),
              ],
            ),
            if (showPendingBadge)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Align(
                  alignment: Alignment.center,
                  child: AppBadge(
                    label: l10n.predictionPendingResultLabel,
                    tone: AppBadgeTone.muted,
                  ),
                ),
              ),
            if (showEditableControls) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              // Two compact controls, not a full-width row — the submit
              // check stays at the RTL leading (visual left) edge and the
              // double toggle at the trailing (visual right) edge, with the
              // Spacer leaving everything else on the card untouched.
              Row(
                children: <Widget>[
                  Flexible(
                    child: _DoubleGlowButton(
                      selected: _isDouble,
                      enabled: enabled,
                      onTap: _toggleDouble,
                      fixtureId: fixtureId,
                    ),
                  ),
                  const Spacer(),
                  _SubmitButton(
                    key: Key('currentMonthFixtures.submit.$fixtureId'),
                    enabled: enabled && hasPick,
                    inFlight: inFlight,
                    tooltip: l10n.submitFixturePredictionButton,
                    onTap: _submit,
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

/// The header row: league logo + name + (optional) kickoff time on the
/// leading (RTL: right) side, an "open leaderboard" icon button on the
/// trailing (RTL: left) side.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.competitionId,
    required this.competitionName,
    required this.kickoffAt,
    required this.onOpenLeaderboard,
  });

  final String competitionId;
  final String competitionName;
  final String? kickoffAt;
  final VoidCallback onOpenLeaderboard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final String? assetPath = competitionLogoAsset(competitionId);
    final Color logoTint =
        competitionLogoBrandColor(competitionId) ?? tokens.surfaceHigh;
    final DateTime? kickoffLocal = kickoffAt == null
        ? null
        : DateTime.tryParse(kickoffAt!)?.toLocal();

    return Row(
      children: <Widget>[
        _CompetitionLogo(
          name: competitionName,
          assetPath: assetPath,
          tint: logoTint,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            competitionName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
          ),
        ),
        if (kickoffLocal != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          Text('•', style: TextStyle(color: tokens.textMuted)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            intl.DateFormat.jm(
              Localizations.localeOf(context).toString(),
            ).format(kickoffLocal),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: l10n.viewLeaderboardTooltip,
          icon: Icon(Icons.open_in_new_rounded, color: tokens.textSecondary),
          iconSize: AppSizes.iconSm,
          constraints: const BoxConstraints(
            minWidth: AppSizes.minTouchTarget,
            minHeight: AppSizes.minTouchTarget,
          ),
          onPressed: onOpenLeaderboard,
        ),
      ],
    );
  }
}

/// The 18×18 league logo, or a letter-fallback circle when no asset is on
/// file (`competition_logo_assets.dart` ships empty today — see its doc) —
/// same "never a blank box" rule `TeamLogo` already follows.
class _CompetitionLogo extends StatelessWidget {
  const _CompetitionLogo({
    required this.name,
    required this.assetPath,
    required this.tint,
  });

  final String name;
  final String? assetPath;
  final Color tint;

  static const double _size = 18;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (assetPath != null) {
      return ClipOval(
        child: Image.asset(
          assetPath!,
          width: _size,
          height: _size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _fallback(context, tokens),
        ),
      );
    }
    return _fallback(context, tokens);
  }

  Widget _fallback(BuildContext context, AppTokens tokens) {
    final String trimmed = name.trim();
    final String initials = trimmed.isEmpty
        ? '?'
        : trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            initials,
            maxLines: 1,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ),
      ),
    );
  }
}

/// One side's crest + name — a plain presentational widget: identity is
/// resolved once by the parent card (which already watches
/// [teamCatalogProvider] for the shared gradient/glow calculation), not
/// re-resolved per side. The crest itself sits on a small brand-color glow
/// (a soft halo scoped to the logo, distinct from the card's wider ambient
/// glow) — only drawn when a real brand color was resolved, never a guess;
/// the logo's own size/position are untouched, the glow is purely an extra
/// layer behind it.
class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.displayName,
    required this.crestUrl,
    required this.brandColor,
  });

  final String displayName;
  final String? crestUrl;
  final Color? brandColor;

  static const double _glowSize = AppSizes.iconXl + AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (brandColor != null)
              Container(
                width: _glowSize,
                height: _glowSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: brandColor!.withValues(
                        alpha: AppOpacity.crestGlow,
                      ),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            TeamLogo(
              displayName: displayName,
              crestUrl: crestUrl,
              brandColor: brandColor,
              size: AppSizes.iconXl,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The fixed-width middle slot between the two [_TeamColumn]s — one of
/// three mutually exclusive contents (§6 of the spec, most specific first):
/// graded (forecast + points), locked (lock icon + "Started"), or the two
/// active [_ScoreStepper]s (open/predicted — steppers stay active and
/// pre-filled once predicted, per the spec's own table).
class _MiddleSlot extends StatelessWidget {
  const _MiddleSlot({
    required this.isGraded,
    required this.locked,
    required this.myPrediction,
    required this.grade,
    required this.points,
    required this.homeGoals,
    required this.awayGoals,
    required this.enabled,
    required this.showEditableControls,
    required this.fixtureId,
    required this.onIncrementHome,
    required this.onDecrementHome,
    required this.onIncrementAway,
    required this.onDecrementAway,
  });

  final bool isGraded;
  final bool locked;
  final FixturePredictionDto? myPrediction;
  final String? grade;
  final int? points;
  final int? homeGoals;
  final int? awayGoals;
  final bool enabled;
  final bool showEditableControls;
  final String fixtureId;
  final VoidCallback onIncrementHome;
  final VoidCallback onDecrementHome;
  final VoidCallback onIncrementAway;
  final VoidCallback onDecrementAway;

  @override
  Widget build(BuildContext context) {
    if (isGraded && myPrediction != null) {
      return _GradedSlot(
        prediction: myPrediction!,
        grade: grade,
        points: points,
      );
    }
    if (locked) {
      return const _LockedSlot();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ScoreStepper(
          value: homeGoals,
          enabled: enabled,
          onIncrement: onIncrementHome,
          onDecrement: onDecrementHome,
          fixtureId: fixtureId,
          side: 'home',
        ),
        const SizedBox(width: AppSpacing.sm),
        _ScoreStepper(
          value: awayGoals,
          enabled: enabled,
          onIncrement: onIncrementAway,
          onDecrement: onDecrementAway,
          fixtureId: fixtureId,
          side: 'away',
        ),
      ],
    );
  }
}

class _GradedSlot extends StatelessWidget {
  const _GradedSlot({
    required this.prediction,
    required this.grade,
    required this.points,
  });

  final FixturePredictionDto prediction;
  final String? grade;
  final int? points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool success =
        grade == 'exact_scoreline' || grade == 'correct_outcome';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ScorePill(home: prediction.homeGoals, away: prediction.awayGoals),
        const SizedBox(height: AppSpacing.xs),
        if (points != null)
          AppBadge(
            label: l10n.pointsAbbreviated(points!),
            tone: success ? AppBadgeTone.success : AppBadgeTone.muted,
            icon: grade == 'exact_scoreline' ? Icons.star : null,
          ),
      ],
    );
  }
}

class _LockedSlot extends StatelessWidget {
  const _LockedSlot();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
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
          style: TextStyle(color: tokens.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

/// One side's numeric score stepper: `+` on top, the value (or "?" when
/// unset) in the middle, `-` on the bottom. `null` shows "?"; the first `+`
/// press moves it to `0`, the first `-` press from `null` (or from `0`) is a
/// no-op (never negative). Range `0..99`; a button at its boundary is
/// disabled visually ([AppOpacity.disabled]), never hidden.
class _ScoreStepper extends StatelessWidget {
  const _ScoreStepper({
    required this.value,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
    required this.fixtureId,
    required this.side,
  });

  final int? value;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String fixtureId;
  final String side;

  static const double _width = 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool canIncrement = enabled && (value ?? -1) < 99;
    final bool canDecrement = enabled && value != null && value! > 0;

    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brButton,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepperZone(
            key: Key('currentMonthFixtures.$side.increment.$fixtureId'),
            icon: Icons.add_rounded,
            tooltip: l10n.scoreStepperIncreaseTooltip,
            height: AppSizes.minTouchTarget,
            onTap: canIncrement ? onIncrement : null,
          ),
          Container(
            height: 32,
            alignment: Alignment.center,
            child: Text(
              value?.toString() ?? '?',
              key: Key('currentMonthFixtures.$side.value.$fixtureId'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: value == null ? tokens.textMuted : tokens.textPrimary,
              ),
            ),
          ),
          _StepperZone(
            key: Key('currentMonthFixtures.$side.decrement.$fixtureId'),
            icon: Icons.remove_rounded,
            tooltip: l10n.scoreStepperDecreaseTooltip,
            height: AppSizes.minTouchTarget,
            onTap: canDecrement ? onDecrement : null,
          ),
        ],
      ),
    );
  }
}

class _StepperZone extends StatelessWidget {
  const _StepperZone({
    required this.icon,
    required this.tooltip,
    required this.height,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bool enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Icon(icon, size: AppSizes.iconMd, color: tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The "make it double" toggle — a compact pill (not a full-width bar):
/// unselected is a muted surface fill with a gold icon/border accent,
/// selected is a gold→bronze gradient fill with an ambient gold glow and
/// the filled bolt icon. The state is never color-alone — the icon and
/// border width both change with it too (accessibility). Reuses the same
/// key the prior chip design used (`currentMonthFixtures.double.$fixtureId`)
/// — same control, restyled smaller so it no longer competes for width with
/// the submit control.
class _DoubleGlowButton extends StatelessWidget {
  const _DoubleGlowButton({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.fixtureId,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String fixtureId;

  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final String label = l10n.predictionMakeItDoubleLabel;

    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          key: Key('currentMonthFixtures.double.$fixtureId'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.brButton,
              gradient: selected
                  ? LinearGradient(colors: <Color>[tokens.gold, tokens.bronze])
                  : null,
              color: selected ? null : tokens.surfaceElevated,
              border: Border.all(
                color: selected
                    ? tokens.gold
                    : tokens.gold.withValues(alpha: 0.35),
                width: selected ? AppStroke.selected : AppStroke.regular,
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: tokens.gold.withValues(alpha: 0.40),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  selected ? Icons.bolt_rounded : Icons.bolt_outlined,
                  size: AppSizes.iconSm,
                  color: selected ? tokens.onPrimary : tokens.gold,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: selected ? tokens.onPrimary : tokens.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact submit control — a small circular success-green check,
/// sized to the accessible minimum touch target even though its visible
/// footprint is tighter than the old full-width bar. Icon-only, so it
/// carries an explicit [Tooltip]/semantic label instead of visible text.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.enabled,
    required this.inFlight,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final bool enabled;
  final bool inFlight;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: AppSizes.minTouchTarget,
        height: AppSizes.minTouchTarget,
        child: Material(
          shape: const CircleBorder(),
          color: enabled ? tokens.successContainer : tokens.surfaceElevated,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Center(
              child: inFlight
                  ? SizedBox(
                      width: AppSizes.progressSm,
                      height: AppSizes.progressSm,
                      child: CircularProgressIndicator(
                        strokeWidth: AppSizes.progressStroke,
                        color: tokens.success,
                      ),
                    )
                  : Icon(
                      Icons.check_rounded,
                      color: enabled ? tokens.success : tokens.textMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
