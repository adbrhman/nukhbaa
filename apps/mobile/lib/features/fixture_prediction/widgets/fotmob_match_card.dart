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
///    steppers stay active, pre-filled from the stored prediction. (A
///    standalone "pending result" badge used to render under the body here
///    too; removed in the reference-parity pass below — it added a fourth
///    row with no counterpart in the reference, and the graded state
///    already carries its own status right next to the score.)
/// 4. **Open** (no prediction yet, not locked) — steppers start at `null`
///    ("?"), submit stays disabled until both sides have a value.
///
/// ## Reference-parity pass (corrections, recorded)
/// A follow-up review against the FotMob reference found the card reading
/// heavier/more saturated than intended: an outer card-level BoxShadow/glow
/// with no reference counterpart (removed outright — separation between
/// cards is the border + margin alone now); a full-width horizontal
/// gradient wash instead of two faint radial glows confined to the top
/// corners (replaced, and read through the new `AppTokens.tintStrength`
/// rather than `Theme.of(context).brightness` inside this widget); score
/// steppers whose `tokens.surfaceElevated` fill read almost black in dark
/// mode (switched to `tokens.textPrimary.withValues(alpha: 0.08)`, wider
/// and taller); the double toggle defaulting to a solid-gold, glowing
/// unselected state that dominated the card (now quiet/neutral by default,
/// solid gold only once selected); the submit control fluctuating between
/// an unrelated success-green and the double button's own gold instead of
/// signaling readiness via `tokens.primary`; the league name truncating
/// behind a fixed-width kickoff time; and the competition-logo fallback
/// showing the same two Arabic letters ("ال") for nearly every league
/// (replaced with a generic trophy glyph).
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
    // "Confirmed" drives the small checkmark badge between the steppers:
    // either this submit just succeeded, or the current pick already
    // matches what's stored server-side (predicted state, unedited).
    final bool matchesSavedPrediction =
        myPrediction != null &&
        myPrediction.homeGoals == _homeGoals &&
        myPrediction.awayGoals == _awayGoals;
    final bool isConfirmed =
        submission is FixtureSubmissionSucceeded || matchesSavedPrediction;
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
    // A locked card's corner glow is halved, not removed — a full-strength
    // glow on a card the user can no longer act on read as an error state.
    final double tint = tokens.tintStrength * (locked ? 0.5 : 1.0);

    return Container(
      key: Key('currentMonthFixtures.fixture.$fixtureId'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: tokens.border, width: AppStroke.hairline),
        color: tokens.surface,
      ),
      child: Stack(
        children: <Widget>[
          // Two faint radial washes at the top corners only — the reference
          // has no full-bleed team-color gradient and no card-level
          // BoxShadow/halo; separation between cards comes from the border
          // and margin alone.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.0, -1.0),
                    radius: 0.9,
                    colors: <Color>[
                      _cornerGlow(home.brandColor, tint),
                      Colors.transparent,
                    ],
                    stops: const <double>[0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.0, -1.0),
                    radius: 0.9,
                    colors: <Color>[
                      _cornerGlow(away.brandColor, tint),
                      Colors.transparent,
                    ],
                    stops: const <double>[0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
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
                      isConfirmed: isConfirmed,
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
                if (showEditableControls) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: <Widget>[
                      _DoubleGlowButton(
                        selected: _isDouble,
                        enabled: enabled,
                        onTap: _toggleDouble,
                        fixtureId: fixtureId,
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
                        key: Key(
                          'currentMonthFixtures.failure.message.$fixtureId',
                        ),
                        style: TextStyle(color: tokens.error, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The corner-glow color for one side of the card: the team's own resolved
/// brand color washed to [tint], or fully transparent (never a guessed
/// fallback color) when no brand color was resolved.
Color _cornerGlow(Color? brandColor, double tint) => brandColor == null
    ? Colors.transparent
    : brandColor.withValues(alpha: tint);

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
    final DateTime? kickoffLocal = kickoffAt == null
        ? null
        : DateTime.tryParse(kickoffAt!)?.toLocal();

    // A single Flexible wrapping the whole leading group (logo + name +
    // time), with the icon button as the row's only other, non-flex child
    // and MainAxisAlignment.spaceBetween pushing it to the far end. Using a
    // Spacer here instead would give the name and the Spacer an EQUAL share
    // of the leftover width (both are flex:1 by default), starving the name
    // of space it should get in full — that was the actual cause of the
    // truncation this replaces.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _CompetitionLogo(assetPath: assetPath),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  competitionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              if (kickoffLocal != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
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
                ),
            ],
          ),
        ),
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

/// The 16×16 league logo, or a generic trophy-glyph fallback when no asset
/// is on file (`competition_logo_assets.dart` ships empty today — see its
/// doc). A two-letter initials fallback would repeat the same two Arabic
/// letters ("ال", the definite article) for nearly every league name here,
/// which reads as a bug rather than an identity mark — the trophy glyph
/// reads clearly as "no logo yet" instead.
class _CompetitionLogo extends StatelessWidget {
  const _CompetitionLogo({required this.assetPath});

  final String? assetPath;

  static const double _size = 16;

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
          errorBuilder: (context, error, stackTrace) => _fallback(tokens),
        ),
      );
    }
    return _fallback(tokens);
  }

  Widget _fallback(AppTokens tokens) {
    return Icon(
      Icons.emoji_events_outlined,
      size: _size,
      color: tokens.textMuted,
    );
  }
}

/// One side's crest + name — a plain presentational widget: identity is
/// resolved once by the parent card (which already watches
/// [teamCatalogProvider]). The crest renders bare — no glow/halo or
/// colored backdrop behind it, in any state — per the reference.
class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.displayName,
    required this.crestUrl,
    required this.brandColor,
  });

  final String displayName;
  final String? crestUrl;
  final Color? brandColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TeamLogo(
          displayName: displayName,
          crestUrl: crestUrl,
          brandColor: brandColor,
          size: AppSizes.iconXl,
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
    required this.isConfirmed,
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

  /// Whether the current pick is a confirmed one — either just submitted
  /// successfully, or matches an already-stored prediction. Drives the
  /// small checkmark badge between the two steppers (hidden entirely in
  /// the locked/graded states, since this branch never runs for those).
  final bool isConfirmed;
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
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        Row(
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
            const SizedBox(width: AppSpacing.xs),
            _ScoreStepper(
              value: awayGoals,
              enabled: enabled,
              onIncrement: onIncrementAway,
              onDecrement: onDecrementAway,
              fixtureId: fixtureId,
              side: 'away',
            ),
          ],
        ),
        if (homeGoals != null && awayGoals != null)
          _ConfirmBadge(confirmed: isConfirmed),
      ],
    );
  }
}

/// The small badge that floats over the gap between the two
/// [_ScoreStepper]s once both sides have a value — centered on the whole
/// [_MiddleSlot] Stack, which lands it horizontally on the gap and
/// vertically level with the digit row (the stepper's `+`/`-` zones are
/// symmetric above and below it). Unconfirmed: an outlined, muted check.
/// Confirmed (just submitted, or already matches a stored prediction):
/// solid [AppTokens.primary] fill. No shadow in either state.
class _ConfirmBadge extends StatelessWidget {
  const _ConfirmBadge({required this.confirmed});

  final bool confirmed;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return Semantics(
      label: l10n.predictionScorePickedLabel,
      child: Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: confirmed
              ? tokens.primary
              : tokens.textPrimary.withValues(alpha: 0.10),
          border: confirmed
              ? null
              : Border.all(
                  color: tokens.textPrimary.withValues(alpha: 0.12),
                  width: AppStroke.hairline,
                ),
        ),
        child: Icon(
          Icons.check_rounded,
          size: 16,
          color: confirmed ? tokens.onPrimary : tokens.textSecondary,
        ),
      ),
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

  static const double _width = 68;
  static const double _height = 92;
  static const double _zoneHeight = 28;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool canIncrement = enabled && (value ?? -1) < 99;
    final bool canDecrement = enabled && value != null && value! > 0;
    final Color divider = tokens.textPrimary.withValues(alpha: 0.06);

    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: tokens.textPrimary.withValues(alpha: 0.06),
        borderRadius: AppRadius.brCard,
        border: Border.all(
          color: tokens.textPrimary.withValues(alpha: 0.12),
          width: AppStroke.hairline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _StepperZone(
            key: Key('currentMonthFixtures.$side.increment.$fixtureId'),
            icon: Icons.add_rounded,
            tooltip: l10n.scoreStepperIncreaseTooltip,
            height: _zoneHeight,
            onTap: canIncrement ? onIncrement : null,
          ),
          Divider(
            height: AppStroke.hairline,
            thickness: AppStroke.hairline,
            color: divider,
          ),
          Expanded(
            child: Container(
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
          ),
          Divider(
            height: AppStroke.hairline,
            thickness: AppStroke.hairline,
            color: divider,
          ),
          _StepperZone(
            key: Key('currentMonthFixtures.$side.decrement.$fixtureId'),
            icon: Icons.remove_rounded,
            tooltip: l10n.scoreStepperDecreaseTooltip,
            height: _zoneHeight,
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
            child: Icon(
              icon,
              size: AppSizes.iconSm,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The "make it double" toggle — quiet by default so it never competes
/// with the rest of the card: unselected carries no gold and no glow at
/// all, just a faint neutral fill/border. Selected is a solid gold fill
/// (no gradient) with one small ambient shadow. The state is never
/// color-alone — the icon and fill both change with it too
/// (accessibility). Reuses the same key the prior chip design used
/// (`currentMonthFixtures.double.$fixtureId`) — same control, restyled.
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

  static const double _height = 36;

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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.brButton,
              color: selected
                  ? tokens.gold
                  : tokens.textPrimary.withValues(alpha: 0.06),
              border: selected
                  ? null
                  : Border.all(
                      color: tokens.textPrimary.withValues(alpha: 0.12),
                      width: AppStroke.hairline,
                    ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: tokens.gold.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
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
                  color: selected ? tokens.onPrimary : tokens.textSecondary,
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
                      color: selected ? tokens.onPrimary : tokens.textSecondary,
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

/// The compact submit control — only turns [tokens.primary] blue once a
/// pick actually exists to submit; otherwise it stays as quiet as the
/// double button's own default state, so it never out-shouts the card's
/// content. Same rounded-rect radius as the double button, no shadow in
/// either state. Icon-only, so it carries an explicit [Tooltip]/semantic
/// label instead of visible text.
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

  static const double _width = 44;
  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _width,
        height: _height,
        child: Material(
          borderRadius: AppRadius.brButton,
          color: enabled
              ? tokens.primary
              : tokens.textPrimary.withValues(alpha: 0.06),
          child: InkWell(
            borderRadius: AppRadius.brButton,
            onTap: enabled ? onTap : null,
            child: Center(
              child: inFlight
                  ? SizedBox(
                      width: AppSizes.progressSm,
                      height: AppSizes.progressSm,
                      child: CircularProgressIndicator(
                        strokeWidth: AppSizes.progressStroke,
                        color: tokens.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.check_rounded,
                      size: AppSizes.iconSm,
                      color: enabled ? tokens.onPrimary : tokens.textMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
