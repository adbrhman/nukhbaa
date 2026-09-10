// ignore_for_file: unused_element
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
import '../../history/prediction_lookup_providers.dart';
import '../../leaderboards/season_leaderboard_screen.dart';
import '../fixture_prediction_controller.dart';
import '../fixture_prediction_submission.dart';
import 'live_matches_chip.dart';

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

    final AsyncValue<Map<String, FixturePredictionDto>> myPredictionsAsync = ref
        .watch(myFixturePredictionsByFixtureProvider);
    final FixturePredictionDto? myPrediction =
        myPredictionsAsync.value?[_fixture.fixtureId];

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
    // Reference-parity card surface: dark grey center with a restrained
    // team-colored wash on each team's own side. The actual crest glow is
    // handled by [_TeamColumn] and uses the same resolved team color.
    final Color cardBase = tokens.isDark
        ? const Color(0xFF2F2F2F)
        : tokens.surface;
    final double intensity = locked ? 0.62 : 1.0;
    final double edgeTint = (tokens.isDark ? 0.18 : 0.07) * intensity;
    final double innerTint = (tokens.isDark ? 0.06 : 0.025) * intensity;
    final Color homeEdge = Color.lerp(
      cardBase,
      home.brandColor ?? cardBase,
      edgeTint,
    )!;
    final Color homeInner = Color.lerp(
      cardBase,
      home.brandColor ?? cardBase,
      innerTint,
    )!;
    final Color awayInner = Color.lerp(
      cardBase,
      away.brandColor ?? cardBase,
      innerTint,
    )!;
    final Color awayEdge = Color.lerp(
      cardBase,
      away.brandColor ?? cardBase,
      edgeTint,
    )!;

    return Container(
      key: Key('currentMonthFixtures.fixture.$fixtureId'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brCardLarge,
        border: Border.all(color: tokens.border, width: AppStroke.hairline),
        color: cardBase,
      ),
      child: Stack(
        children: <Widget>[
          // Keep the tint attached to the team's visual side. Directional
          // alignment is essential here: Arabic RTL puts the home team on the
          // right, while LTR puts it on the left.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: <Color>[
                      homeEdge,
                      homeInner,
                      cardBase,
                      awayInner,
                      awayEdge,
                    ],
                    stops: const <double>[0.0, 0.22, 0.5, 0.78, 1.0],
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
                  // The league the match was played in when known, falling
                  // back to the contest's own name ("شهر 9") only while a
                  // fixture still carries no league. The reference design
                  // shows the league here, never the contest.
                  competitionId: widget.item.competitionId,
                  competitionName:
                      _fixture.leagueName ?? widget.item.competitionName,
                  leagueLogoUrl: _fixture.leagueLogoUrl,
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
                        assetPath: home.assetPath,
                        brandColor: home.brandColor,
                      ),
                    ),
                    _MiddleSlot(
                      isGraded: isGraded,
                      locked: locked,
                      live: locked && isFixtureLive(_fixture.kickoffAt),
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
                        assetPath: away.assetPath,
                        brandColor: away.brandColor,
                      ),
                    ),
                  ],
                ),
                if (showEditableControls) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
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
                      const SizedBox(width: AppSpacing.sm),
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
    required this.leagueLogoUrl,
    required this.kickoffAt,
    required this.onOpenLeaderboard,
  });

  final String competitionId;
  final String competitionName;

  /// The league's own logo when the fixture carries one — preferred over the
  /// bundled per-competition asset, which ships empty.
  final String? leagueLogoUrl;
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
              _CompetitionLogo(assetPath: assetPath, logoUrl: leagueLogoUrl),
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
  const _CompetitionLogo({required this.assetPath, this.logoUrl});

  final String? assetPath;

  /// A remote league logo (`football_data.leagues.logo_url`, migration
  /// 0027). Preferred over [assetPath] because the bundled asset map ships
  /// empty; falls through to the trophy glyph on a network/decode failure,
  /// exactly as the asset path does.
  final String? logoUrl;

  static const double _size = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String? url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: _size,
          height: _size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _fallback(tokens),
        ),
      );
    }
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

/// One side's crest + name — identity is resolved once by the parent card.
/// The small halo is intentionally local to the crest and uses the same
/// dynamic brand color as the side tint; it is visible, but never dominant.
class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.displayName,
    required this.crestUrl,
    required this.assetPath,
    required this.brandColor,
  });

  final String displayName;
  final String? crestUrl;
  final String? assetPath;
  final Color? brandColor;

  /// Local to this card so the shared `AppSizes.iconXl` token keeps its
  /// meaning for every other screen that reads it. 34 is the reference's
  /// own crest, measured off the screenshot: 91px wide at a 1080px/2.75x
  /// capture. The previous 56 was ~65% larger and was what made the card
  /// read as crest-first rather than score-first.
  static const double _crestSize = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: _crestSize + 10,
          height: _crestSize + 10,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: brandColor == null
                ? const <BoxShadow>[]
                : <BoxShadow>[
                    BoxShadow(
                      color: brandColor!.withValues(alpha: 0.20),
                      blurRadius: 14,
                      spreadRadius: 0.5,
                    ),
                  ],
          ),
          child: TeamLogo(
            displayName: displayName,
            crestUrl: crestUrl,
            assetPath: assetPath,
            brandColor: brandColor,
            size: _crestSize,
          ),
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
    required this.live,
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

  /// Locked AND inside [liveWindow] after kickoff (a time estimate, see
  /// [isFixtureLive]); drives "live" vs "awaiting result" in [_LockedSlot].
  final bool live;
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
      return _LockedSlot(live: live);
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
    // Tone follows the server's points, not the grade name: a correct
    // outcome can award 0 under the frozen ruleset, and a green "0 pts"
    // reads as a win nobody got.
    final bool success = (points ?? 0) > 0;
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

/// A started, not-yet-graded fixture: "live" (red dot) inside the
/// [liveWindow] after kickoff, then "awaiting result" -- instead of one
/// generic "started" label for both, which kept a finished match looking
/// like it was still being played.
class _LockedSlot extends StatelessWidget {
  const _LockedSlot({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final Color color = live ? tokens.error : tokens.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          live ? Icons.circle : Icons.lock_outline,
          size: live ? 10 : AppSizes.iconSm,
          color: color,
        ),
        const SizedBox(height: 2),
        Text(
          live ? l10n.fixturesLiveLabel : l10n.predictionPendingResultLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 11),
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

  // Measured off the reference screenshot (1080px capture, 2.75x): the
  // stepper box is 167px wide there, i.e. 61 logical, not 68. Height and
  // tap-zone follow at the same ratio so the box keeps its proportions.
  static const double _width = 61;
  static const double _height = 82;
  static const double _zoneHeight = 26;

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
