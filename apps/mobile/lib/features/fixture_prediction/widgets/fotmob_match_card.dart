// ignore_for_file: unused_element
/// The FotMob-style match card (`match-card-fotmob-spec.md`) — replaces
/// `current_month_fixtures_screen.dart`'s former `_CurrentMonthFixtureCard`
/// as the one card `CurrentMonthFixturesScreen` renders per fixture. Lives
/// under `features/fixture_prediction/widgets/` (not `core/ui/`) because it
/// needs [resolveTeamIdentity] + `teamCatalogProvider`, and `core/ui/**` may
/// never import `features/**` (`import_lint`).
///
/// Reuses the existing per-fixture submit slice. The card computes no point,
/// rank, or probability of its own — scores are saved through the existing
/// [fixturePredictionControllerProvider], while the win percentages are
/// server-computed and arrive on the feed item itself (they were once a
/// per-card GET; see the build method).
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
///    ("?"), and the prediction auto-saves once both sides have a value.
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
/// ## Auto-save
/// Every score change schedules one debounced server submission. The small
/// check badge between the steppers becomes solid blue only after the server
/// confirms the current values. The existing controller remains the sole
/// prediction-write path.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/app_typography.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_opacity.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_stroke.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
import '../../../core/format/timestamps.dart';
import '../../../core/time/riyadh_day_turnover.dart';
import '../../../core/ui/app_badge.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../../core/ui/score_pill.dart';
import '../../../core/ui/team_logo.dart';
import '../../../l10n/app_localizations.dart';
import '../../competition/competition_logo_assets.dart';
import '../../competition/team_catalog_index.dart';
import '../../competition/team_registry.dart';
import '../../competition/team_identity.dart';
import '../../duels/duel_offer.dart';
import '../../history/my_fixture_scores_providers.dart';
import '../../history/prediction_history_providers.dart';
import '../../history/prediction_lookup_providers.dart';
import '../../leaderboards/season_leaderboard_screen.dart';
import '../../notifications/favorite_team_offer.dart';
import '../feed_refresh_signal.dart';
import '../fixture_prediction_controller.dart';
import '../fixture_prediction_submission.dart';
import 'fixture_predictions_board_page.dart';
import 'live_matches_chip.dart';
import 'match_details_page.dart';

/// Fewest decisive predictions a win share is shown for: over one call a
/// share read "100%", a verdict it is not (decided 2026-10-07). Below it
/// the card before kickoff reads 0% on both sides (decided 2026-10-11).
const int minShareSample = 5;

/// The server's refusal of a second double on the same day.
const String _dailyDoubleExceededCode = 'prediction.daily_double_exceeded';

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
  // ValueNotifier (not setState) so a +/- tap repaints only the
  // _MiddleSlot subtree (steppers + confirm badge), not the whole card.
  final ValueNotifier<int?> _homeGoals = ValueNotifier<int?>(null);
  final ValueNotifier<int?> _awayGoals = ValueNotifier<int?>(null);
  bool _isDouble = false;
  bool _prefilledFromPrediction = false;
  Timer? _autoSaveTimer;

  /// The controller captured while this card was still mounted, so a save
  /// that is still pending when the card goes away can be flushed from
  /// [dispose] without reaching for `ref` after it is gone.
  FixturePredictionController? _saveTarget;

  SeasonFixtureCardDto get _fixture => widget.item.fixture;

  @override
  void initState() {
    super.initState();
    // The history is usually already cached by the time a card is built, and
    // reading it here rather than in build() is what keeps the prefill out of
    // the build phase entirely.
    _applyPrefill(
      ref
          .read(myFixturePredictionsByFixtureProvider)
          .value?[_fixture.fixtureId],
    );
  }

  /// Fills the steppers from an existing [prediction], exactly once.
  ///
  /// Never from build(): writing a `ValueNotifier` there notifies the
  /// `ListenableBuilder` below in the middle of the frame that is building it,
  /// and `_isDouble` was being changed with no `setState` at all. The two
  /// entry points are [initState] (the prediction was already cached) and the
  /// `ref.listen` in build (it arrived later). Returns whether anything
  /// changed, so the caller can decide about repainting.
  bool _applyPrefill(FixturePredictionDto? prediction) {
    if (_prefilledFromPrediction || prediction == null) return false;
    _prefilledFromPrediction = true;
    _homeGoals.value = prediction.homeGoals;
    _awayGoals.value = prediction.awayGoals;
    _isDouble = prediction.isDouble;
    return true;
  }

  /// The list now keys every card by fixture id, so a State should never
  /// outlive its fixture. This is the second guard: if a card is ever handed
  /// a different fixture anyway, it starts clean rather than presenting the
  /// previous match's scoreline as if it were this one's.
  @override
  void didUpdateWidget(covariant FotmobMatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.fixture.fixtureId == _fixture.fixtureId) return;
    _autoSaveTimer?.cancel();
    _saveTarget = null;
    _homeGoals.value = null;
    _awayGoals.value = null;
    _isDouble = false;
    _prefilledFromPrediction = false;
  }

  bool get _isLocked {
    final kickoff = _fixture.kickoffAt;
    if (kickoff == null) return false;
    final parsed = DateTime.tryParse(kickoff)?.toUtc();
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now().toUtc());
  }

  FixturePredictionKey get _key =>
      (seasonId: _fixture.seasonId, fixtureId: _fixture.fixtureId);

  void _incrementHome() {
    _homeGoals.value = ((_homeGoals.value ?? -1) + 1).clamp(0, 99);
    _scheduleAutoSave();
  }

  void _decrementHome() {
    final int? value = _homeGoals.value;
    if (value == null || value <= 0) return;
    _homeGoals.value = value - 1;
    _scheduleAutoSave();
  }

  void _incrementAway() {
    _awayGoals.value = ((_awayGoals.value ?? -1) + 1).clamp(0, 99);
    _scheduleAutoSave();
  }

  void _decrementAway() {
    final int? value = _awayGoals.value;
    if (value == null || value <= 0) return;
    _awayGoals.value = value - 1;
    _scheduleAutoSave();
  }

  void _toggleDouble() {
    setState(() => _isDouble = !_isDouble);
    _scheduleAutoSave();
  }

  /// How many times a save may reschedule itself before the card gives up.
  ///
  /// The reschedule covers a server that ended up holding values older
  /// than the ones on screen, and a double the server refused; both settle
  /// within a round or two. (A submit already in flight is not waited for
  /// here: the controller keeps the newest one.) Unbounded, a disagreement that
  /// never resolved (the server storing something other than what was sent)
  /// became one submit every 250 ms for as long as the card stayed visible.
  static const int _maxAutoSaveRetries = 4;
  int _autoSaveRetries = 0;

  void _scheduleAutoSave({bool isRetry = false}) {
    if (isRetry) {
      if (_autoSaveRetries >= _maxAutoSaveRetries) return;
      _autoSaveRetries++;
    } else {
      // A fresh tap is not a retry: it restarts the budget.
      _autoSaveRetries = 0;
      // Once the user has touched this card, what they tapped wins: the
      // one-shot prefill from the history must never fire afterwards. On a
      // card with no stored prediction it was still armed, so the first
      // save refreshed the history and the refreshed (older) pick was
      // copied over a tap made while that save was in flight.
      _prefilledFromPrediction = true;
    }
    final int? home = _homeGoals.value;
    final int? away = _awayGoals.value;
    if (home == null || away == null || _isLocked) return;
    _autoSaveTimer?.cancel();
    // Captured now, while `ref` is certainly usable, for the dispose flush.
    _saveTarget = ref.read(fixturePredictionControllerProvider(_key).notifier);
    _autoSaveTimer = Timer(const Duration(milliseconds: 250), () async {
      await _saveLatestPrediction();
    });
  }

  Future<void> _saveLatestPrediction() async {
    final int? home = _homeGoals.value;
    final int? away = _awayGoals.value;
    if (!mounted || home == null || away == null || _isLocked) return;

    // A save still in flight is not waited for here: the controller keeps
    // this one and sends it when that save lands. Waiting here spent the
    // retry budget in about a second, and a slower server then kept the
    // older score while this card showed the newer one.
    final notifier = ref.read(
      fixturePredictionControllerProvider(_key).notifier,
    );
    await notifier.submit(
      homeGoals: home,
      awayGoals: away,
      isDouble: _isDouble,
    );

    if (!mounted) return;
    final submission = ref.read(fixturePredictionControllerProvider(_key));
    if (submission is FixtureSubmissionSucceeded) {
      final saved = submission.prediction;
      if (saved.homeGoals != _homeGoals.value ||
          saved.awayGoals != _awayGoals.value ||
          saved.isDouble != _isDouble) {
        _scheduleAutoSave(isRetry: true);
      } else {
        // The server holds exactly what is on screen: one light tap, the
        // same moment the check badge turns blue. Auto-save has no button,
        // so this is the only "saved" the hand feels.
        unawaited(HapticFeedback.lightImpact());
        // Once per fixture, a bar offers to challenge a friend on it; the
        // card itself keeps its layout.
        offerDuelAfterSave(context: context, ref: ref, fixture: _fixture);
        // Once per session, a player with no favourite team is offered the
        // two teams of the match they just predicted.
        unawaited(
          offerFavoriteTeamAfterSave(
            context: context,
            ref: ref,
            fixture: _fixture,
          ),
        );
      }
    }
  }

  /// Writes a save that was still inside its debounce window when the card
  /// went away.
  ///
  /// The microtask is not optional. By the time a State's dispose() runs,
  /// StatefulElement.unmount has ALREADY marked the element defunct, so
  /// mutating a provider from here notifies this very element -- whose
  /// subscription is not closed yet -- and trips markNeedsBuild's assert. One
  /// microtask later the unmount has finished and the subscription is gone,
  /// so the write lands on nobody.
  ///
  /// Guarded, because "the card went away" has two very different causes.
  /// Usually it is a scroll, a switched day or a switched tab: the controller
  /// family is not auto-disposed, so it outlives this widget and the write
  /// completes exactly as it would have. But the card also goes away when the
  /// whole app -- or a test's ProviderScope -- is torn down, and then the
  /// controller is disposed in the same breath and the write has nowhere to
  /// land. That is not a failure worth surfacing: there is no user left to
  /// tell. The throw can arrive synchronously or on the far side of the
  /// request, so both are caught.
  void _flushPendingSave() {
    final int? home = _homeGoals.value;
    final int? away = _awayGoals.value;
    final FixturePredictionController? target = _saveTarget;
    if (home == null || away == null || target == null || _isLocked) return;
    final bool isDouble = _isDouble;
    scheduleMicrotask(() {
      try {
        unawaited(
          target
              .submit(homeGoals: home, awayGoals: away, isDouble: isDouble)
              .catchError((Object _) {}),
        );
      } on Object {
        // The controller went down with the tree; nothing to flush into.
      }
    });
  }

  Future<void> _sharePrediction({
    required int homeGoals,
    required int awayGoals,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String message = l10n.shareHitMessage(
      teamDisplayName(_fixture.homeTeam),
      '$homeGoals-$awayGoals',
      teamDisplayName(_fixture.awayTeam),
    );
    await SharePlus.instance.share(
      ShareParams(
        text: '$message\n${l10n.shareHitJoin('https://nukhbaa.app')}',
      ),
    );
  }

  @override
  void dispose() {
    // A card scrolled out of view, a switched day, a switched tab: each used
    // to take a pending 250 ms auto-save down with it, so a tap made just
    // before leaving was silently never written. The controller family is
    // not auto-disposed, so the submit can still finish on its own.
    final Timer? pending = _autoSaveTimer;
    _autoSaveTimer = null;
    if (pending != null && pending.isActive) {
      pending.cancel();
      _flushPendingSave();
    }
    _homeGoals.dispose();
    _awayGoals.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // The win shares ride along with the feed, so refreshing them after
          // your own vote used to mean refetching the entire month here --
          // once per saved prediction. Raise a flag instead; the screen's
          // minute tick and pull-to-refresh are what actually reload it.
          ref.read(feedRefreshSignalProvider.notifier).request();
        }
        if (next is FixtureSubmissionFailed &&
            next.error.code == _dailyDoubleExceededCode &&
            _isDouble &&
            mounted) {
          // The day's double is already on another match. The toggle stayed
          // lit, claiming a double the server had refused: turn it off, say
          // why, and save the scoreline on its own.
          setState(() => _isDouble = false);
          AppSnackbar.show(context, ErrorPresenter.message(next.error));
          _scheduleAutoSave(isRetry: true);
        }
      },
    );

    // The prediction history can resolve after this card is already on
    // screen; that is the only case initState cannot cover.
    ref.listen<AsyncValue<Map<String, FixturePredictionDto>>>(
      myFixturePredictionsByFixtureProvider,
      (previous, next) {
        if (_applyPrefill(next.value?[_fixture.fixtureId]) && mounted) {
          setState(() {});
        }
      },
    );

    final locked = _isLocked;

    final AsyncValue<Map<String, FixturePredictionDto>> myPredictionsAsync = ref
        .watch(myFixturePredictionsByFixtureProvider);
    final FixturePredictionDto? myPrediction =
        myPredictionsAsync.value?[_fixture.fixtureId];

    // PERF: a grade needs the recorded result, which the feed item already
    // carries, so a card watches the caller's points only once it has one.
    // Every card shares the one read of them (myFixtureScoresProvider,
    // script 75): it used to ask for its own match's scores, again every 2
    // minutes while pending (2026-10-11: 'connections in use 8/8, waiting
    // 99'; 2026-10-14/15: 389 timeouts on that route).
    final bool resultRecorded =
        widget.item.resultHomeGoals != null &&
        widget.item.resultAwayGoals != null;
    final MyFixtureScoreDto? myScore =
        myPrediction == null || !locked || !resultRecorded
        ? null
        : myFixtureScoreOf(
            ref.watch(myFixtureScoresProvider).value,
            myPrediction,
          );
    final String? myGrade = myScore?.grade;
    final int? myPoints = myScore?.points;
    final bool isGraded =
        myGrade == 'exact_scoreline' ||
        myGrade == 'correct_outcome' ||
        myGrade == 'incorrect';

    final bool showEditableControls = !locked && !isGraded;
    // Interactivity must NOT depend on an in-flight submit. The auto-save is
    // debounced at 250 ms, and the pause while moving a finger from one
    // stepper to the other is longer than that -- so the save fired and
    // disabled all four +/- zones plus the double toggle for the whole
    // request, making the second side look dead to fast taps. The controller
    // keeps an overlapping submit and sends it once the one in flight
    // lands, and _saveLatestPrediction reschedules itself until the server
    // holds the current value, so the last tap still wins.
    final bool enabled = !locked;
    // Another match on this one's Riyadh day already holds the caller's
    // double (script 128): the toggle says so, instead of a tap the
    // server refuses. This card's own double, stored or just toggled,
    // is never "elsewhere".
    final Map<DateTime, String> doublesByDay = ref.watch(
      myDoubleFixtureByDayProvider,
    );
    final String? kickoffRaw = _fixture.kickoffAt;
    final DateTime? kickoffInstant = kickoffRaw == null
        ? null
        : DateTime.tryParse(kickoffRaw);
    final String? dayDouble = kickoffInstant == null
        ? null
        : doublesByDay[RiyadhDayTurnover.riyadhDayOf(kickoffInstant)];
    final bool doubleTakenElsewhere =
        !_isDouble && dayDouble != null && dayDouble != _fixture.fixtureId;
    // The win shares arrive with the feed item itself. They used to be a
    // separate GET per card, so a twenty-match day opened twenty extra
    // requests over a phone network to learn twenty numbers the feed's own
    // query already had in hand. `null` means the server did not send them
    // (an older build); nobody having predicted is a real 0.
    // Shown as the started card shows them (script 123: open shares):
    // three-way, draws included, from a server that sends it; the two
    // decisive shares from an older one. All zeros until minShareSample
    // calls, for everyone, whether or not they have called it yet.
    final int? total = widget.item.totalPredictions;
    final int? decisive = widget.item.decisivePredictions;
    final bool threeWay = total != null;
    final bool showShares = threeWay
        ? total >= minShareSample
        : decisive == null || decisive >= minShareSample;
    final int homeShare = !showShares
        ? 0
        : threeWay
        ? (widget.item.homeOutcomeShare ?? 0)
        : (widget.item.homeWinPercentage ?? 0);
    final int? drawShare = !threeWay
        ? null
        : showShares
        ? (widget.item.drawOutcomeShare ?? 0)
        : 0;
    final int awayShare = !showShares
        ? 0
        : threeWay
        ? (widget.item.awayOutcomeShare ?? 0)
        : (widget.item.awayWinPercentage ?? 0);
    // The check between the steppers means "this exact pick is saved".
    // Include the double flag so changing it also requires server
    // confirmation. Takes home/away explicitly so it can be re-evaluated
    // per keystroke from inside the ListenableBuilder below, without this
    // whole build() re-running.
    bool isConfirmedFor(int? home, int? away) {
      final bool matchesSavedPrediction =
          myPrediction != null &&
          myPrediction.homeGoals == home &&
          myPrediction.awayGoals == away &&
          myPrediction.isDouble == _isDouble;
      final bool submissionMatchesCurrent =
          submission is FixtureSubmissionSucceeded &&
          submission.prediction.homeGoals == home &&
          submission.prediction.awayGoals == away &&
          submission.prediction.isDouble == _isDouble;
      return submissionMatchesCurrent || matchesSavedPrediction;
    }

    final String fixtureId = _fixture.fixtureId;

    final catalogById = ref.watch(teamCatalogByIdProvider);
    final ResolvedTeamIdentity home = resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: _fixture.homeTeamId,
      teamName: _fixture.homeTeam,
    );
    final ResolvedTeamIdentity away = resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: _fixture.awayTeamId,
      teamName: _fixture.awayTeam,
    );
    // One surface for every card: the team-coloured wash on each side gave
    // each card its own cast, against one semantic colour system
    // (2026-09-24, UI-09). The team colour stays in the crest's halo
    // ([_TeamColumn]).
    final Color cardBase = tokens.surface;

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
          Padding(
            // script 132: card padding -- before kickoff the header's 48px
            // ranking button already carries its own air above and the
            // footer's 48px touch below, so the card adds less of its own.
            padding: locked
                ? const EdgeInsets.all(AppSpacing.md)
                : const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // A test fixture reaches admins only (migration 0098);
                // the label keeps it from passing for a real match.
                if (_fixture.isTest) ...<Widget>[
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppBadge(
                      key: Key('currentMonthFixtures.testBadge'),
                      label: 'مباراة تجريبية',
                      tone: AppBadgeTone.gold,
                      icon: Icons.science_outlined,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                // After kickoff the card turns into the match itself
                // (design of 2026-10-07): status and minute in the header,
                // the score in a box between the sides, the player's call
                // under it, the split of everyone's calls, and the button
                // to everyone's predictions.
                if (locked)
                  _StartedBody(
                    item: widget.item,
                    home: home,
                    away: away,
                    myPrediction: myPrediction,
                    isGraded: isGraded,
                    grade: myGrade,
                    points: myPoints,
                    onOpenPredictions: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FixturePredictionsBoardPage(
                            kickoffAt: _fixture.kickoffAt,
                          ),
                        ),
                      ),
                    ),
                    // The match's story once it is over (script 118).
                    onOpenDetails: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MatchDetailsPage(
                            item: widget.item,
                            home: home,
                            away: away,
                          ),
                        ),
                      ),
                    ),
                  )
                else ...<Widget>[
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
                  // script 132: header gap -- the ranking button's own air.
                  const SizedBox(height: AppSpacing.xs),
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
                      ListenableBuilder(
                        listenable: Listenable.merge(<Listenable>[
                          _homeGoals,
                          _awayGoals,
                        ]),
                        builder: (context, _) {
                          final int? homeGoals = _homeGoals.value;
                          final int? awayGoals = _awayGoals.value;
                          return _MiddleSlot(
                            homeGoals: homeGoals,
                            awayGoals: awayGoals,
                            enabled: enabled,
                            isConfirmed: isConfirmedFor(homeGoals, awayGoals),
                            fixtureId: fixtureId,
                            onIncrementHome: _incrementHome,
                            onDecrementHome: _decrementHome,
                            onIncrementAway: _incrementAway,
                            onDecrementAway: _decrementAway,
                          );
                        },
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
                  // The double sits in the last row, beside the share
                  // (script 128); everyone's calls come first.
                  Padding(
                    // script 132: shares gap.
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    // Under minShareSample calls the card says when the
                    // split will show: zeros read as real figures
                    // (2026-10-19).
                    child: !showShares
                        ? _SharesPending(
                            key: Key(
                              'currentMonthFixtures.sharesPending.$fixtureId',
                            ),
                          )
                        : _OutcomeShares(
                            key: Key(
                              'currentMonthFixtures.outcomeShares.$fixtureId',
                            ),
                            home: homeShare,
                            draw: drawShare,
                            away: awayShare,
                            homeName: home.displayName,
                            awayName: away.displayName,
                          ),
                  ),
                ],
                // The double and the share in one row under everyone's
                // calls (script 128): the share's own row cost every saved
                // card 60px (CARD_HEIGHT, script 127). Both are Flexible:
                // a button's icon row cannot sit unbounded in a Row.
                if (showEditableControls)
                  Padding(
                    key: Key('currentMonthFixtures.footer.$fixtureId'),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Flexible(
                          flex: 3,
                          child: _DoubleGlowButton(
                            selected: _isDouble,
                            enabled: enabled && !doubleTakenElsewhere,
                            takenElsewhere: doubleTakenElsewhere,
                            onTap: _toggleDouble,
                            fixtureId: fixtureId,
                          ),
                        ),
                        if (myPrediction != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            flex: 2,
                            child: ListenableBuilder(
                              listenable: Listenable.merge(<Listenable>[
                                _homeGoals,
                                _awayGoals,
                              ]),
                              builder: (context, _) {
                                final int? shareHome = _homeGoals.value;
                                final int? shareAway = _awayGoals.value;
                                final bool canShare =
                                    shareHome != null &&
                                    shareAway != null &&
                                    isConfirmedFor(shareHome, shareAway);
                                return TextButton.icon(
                                  key: Key(
                                    'currentMonthFixtures.sharePrediction.$fixtureId',
                                  ),
                                  onPressed: canShare
                                      ? () => unawaited(
                                          _sharePrediction(
                                            homeGoals: shareHome,
                                            awayGoals: shareAway,
                                          ),
                                        )
                                      : null,
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).shareHitShareButton,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (submission is FixtureSubmissionFailed)
                  Padding(
                    key: Key('currentMonthFixtures.failure.$fixtureId'),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            ErrorPresenter.message(submission.error),
                            key: Key(
                              'currentMonthFixtures.failure.message.$fixtureId',
                            ),
                            style: TextStyle(
                              color: tokens.errorText,
                              fontSize: AppFontSize.s12,
                            ),
                          ),
                        ),
                        // A dropped connection left the pick unsaved until
                        // the player happened to tap a stepper again.
                        if (!locked &&
                            ErrorPresenter.isRetryable(submission.error))
                          TextButton(
                            key: Key('currentMonthFixtures.retry.$fixtureId'),
                            onPressed: _scheduleAutoSave,
                            child: Text(AppLocalizations.of(context).retry),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
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
    final String? assetPath = competitionLogoAsset(
      competitionId,
      competitionName,
    );
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
          // The kickoff keeps its own width up to half the group, the name
          // takes the rest. A viewer whose date is not Riyadh's reads the
          // weekday after the time (`formatKickoffTime`): that longer label
          // overflowed the row at 320px and at large text (CI at 23:26 UTC,
          // 2026-10-10). Past half the group it now wraps to a second line.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) => Row(
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
                      fontSize: AppFontSize.s12,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                if (kickoffLocal != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Text('•', style: TextStyle(color: tokens.textMuted)),
                  const SizedBox(width: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth.isFinite
                          ? constraints.maxWidth / 2
                          : double.infinity,
                    ),
                    child: Text(
                      formatKickoffTime(context, kickoffAt!),
                      key: const Key('matchCard.kickoff'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.s13,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.viewLeaderboardTooltip,
          // script 123: a ranking, not a link out of the app.
          icon: Icon(Icons.leaderboard_rounded, color: tokens.textSecondary),
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

  /// A logo is drawn whole, a little smaller, on a light disc: logos are
  /// made for light backgrounds (Ligue 1's black mark vanished on the navy
  /// card) and the round clip cut the tall ones (2026-10-07).
  static const double _logoSize = 14;
  static const double _plateSize = 22;

  Widget _plate(Widget logo) => Container(
    key: const Key('competitionLogo.plate'),
    width: _plateSize,
    height: _plateSize,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: logo,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String? url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return _plate(
        Image.network(
          url,
          width: _logoSize,
          height: _logoSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _fallback(tokens),
        ),
      );
    }
    if (assetPath != null) {
      return _plate(
        Image.asset(
          assetPath!,
          width: _logoSize,
          height: _logoSize,
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
        // No blurred halo: a blur shadow behind every crest was re-drawn on
        // every scrolled frame, two per card, which a low-end GPU felt
        // (frame stats, 2026-10-07). The size stays, so nothing moves.
        SizedBox(
          width: _crestSize + 10,
          height: _crestSize + 10,
          child: Center(
            child: TeamLogo(
              displayName: displayName,
              crestUrl: crestUrl,
              assetPath: assetPath,
              brandColor: brandColor,
              size: _crestSize,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Two lines at large text: one line cut long names (UI-18).
        Text(
          displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.s13,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The middle slot between the two [_TeamColumn]s before kickoff: the two
/// active [_ScoreStepper]s, pre-filled once predicted, with the saved check
/// over their gap. After kickoff the whole card is [_StartedBody].
class _MiddleSlot extends StatelessWidget {
  const _MiddleSlot({
    required this.homeGoals,
    required this.awayGoals,
    required this.enabled,
    required this.isConfirmed,
    required this.fixtureId,
    required this.onIncrementHome,
    required this.onDecrementHome,
    required this.onIncrementAway,
    required this.onDecrementAway,
  });

  final int? homeGoals;
  final int? awayGoals;
  final bool enabled;

  /// Whether the current pick is a confirmed one — either just submitted
  /// successfully, or matches an already-stored prediction. Drives the
  /// small checkmark badge between the two steppers.
  final bool isConfirmed;
  final String fixtureId;
  final VoidCallback onIncrementHome;
  final VoidCallback onDecrementHome;
  final VoidCallback onIncrementAway;
  final VoidCallback onDecrementAway;

  @override
  Widget build(BuildContext context) {
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
          // Drawn over the steppers' inner edges: it never takes their tap.
          IgnorePointer(child: _ConfirmBadge(confirmed: isConfirmed)),
      ],
    );
  }
}

/// The circular badge that floats over the gap between the two
/// [_ScoreStepper]s once both sides have a value — centered on the whole
/// [_MiddleSlot] Stack, sized to match the reference card. Unconfirmed: an
/// outlined, muted check. Confirmed (server accepted the current prediction):
/// solid [AppTokens.primary] fill. No shadow in either state.
class _ConfirmBadge extends StatelessWidget {
  const _ConfirmBadge({required this.confirmed});

  final bool confirmed;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return Semantics(
      label: l10n.predictionScorePickedLabel,
      child: Transform.scale(
        scale: 0.5,
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Green means a saved prediction (2026-09-24, UI-26).
            color: confirmed
                ? tokens.success
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
            size: AppSizes.iconMd,
            color: confirmed ? tokens.onSuccess : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One side's numeric score stepper: `+` on top, the value (or "?" when
/// unset) in the middle, `-` on the bottom. `null` shows "?"; the first `+`
/// press moves it to `0`, the first `-` press from `null` (or from `0`) is a
/// no-op (never negative). Range `0..99`; a button at its boundary is
/// disabled visually ([AppOpacity.disabled]), never hidden.
///
/// The touch is the whole box split in two: the upper half adds, the lower
/// half takes away, 48px each -- the bands drawn with `+` and `-` were 26px
/// to touch (UI-01). The drawing keeps the same `+` / value / `-` order.
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
  // stepper box is 167px wide there, i.e. 61 logical, not 68. The height is
  // two 48px touch halves (UI-01) inside the hairline border, which takes
  // its width from each edge; the `+` / `-` bands keep the drawn 26.
  static const double _width = 61;
  static const double _height =
      AppSizes.minTouchTarget * 2 + AppStroke.hairline * 2;
  static const double _iconBand = 26;

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
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(
                child: _StepperZone(
                  key: Key('currentMonthFixtures.$side.increment.$fixtureId'),
                  icon: Icons.add_rounded,
                  tooltip: l10n.scoreStepperIncreaseTooltip,
                  band: _iconBand,
                  alignment: Alignment.topCenter,
                  onTap: canIncrement ? onIncrement : null,
                ),
              ),
              Expanded(
                child: _StepperZone(
                  key: Key('currentMonthFixtures.$side.decrement.$fixtureId'),
                  icon: Icons.remove_rounded,
                  tooltip: l10n.scoreStepperDecreaseTooltip,
                  band: _iconBand,
                  alignment: Alignment.bottomCenter,
                  onTap: canDecrement ? onDecrement : null,
                ),
              ),
            ],
          ),
          // The dividers and the value sit over the two halves and never
          // take a tap from them.
          IgnorePointer(
            child: Column(
              children: <Widget>[
                const SizedBox(height: _iconBand),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: divider,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      value?.toString() ?? '?',
                      key: Key('currentMonthFixtures.$side.value.$fixtureId'),
                      style: TextStyle(
                        fontSize: AppFontSize.s20,
                        fontWeight: FontWeight.w800,
                        color: value == null
                            ? tokens.textMuted
                            : tokens.textPrimary,
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: AppStroke.hairline,
                  thickness: AppStroke.hairline,
                  color: divider,
                ),
                const SizedBox(height: _iconBand),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One touch half of a [_ScoreStepper]: the whole half is the target, and
/// its icon is drawn in the [band] at its outer edge ([alignment]).
class _StepperZone extends StatelessWidget {
  const _StepperZone({
    required this.icon,
    required this.tooltip,
    required this.band,
    required this.alignment,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final double band;
  final Alignment alignment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final VoidCallback? tap = onTap;
    final bool enabled = tap != null;
    return Opacity(
      opacity: enabled ? 1 : AppOpacity.disabled,
      child: Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // A selection tick per step, so a fast run of taps can be
            // counted by feel.
            onTap: tap == null
                ? null
                : () {
                    unawaited(HapticFeedback.selectionClick());
                    tap();
                  },
            child: SizedBox.expand(
              child: Align(
                alignment: alignment,
                child: SizedBox(
                  height: band,
                  width: double.infinity,
                  child: Icon(
                    icon,
                    size: AppSizes.iconSm,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The started card's "everyone's predictions" button, centred under the
/// split of everyone's calls.
class _RevealPredictionsButton extends StatelessWidget {
  const _RevealPredictionsButton({
    required this.fixtureId,
    required this.onTap,
    this.fill = false,
  });

  final String fixtureId;
  final VoidCallback onTap;

  /// Fills its slot, half of a finished card's row (script 119), instead
  /// of standing at its own 200px.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _OutlinedAction(
      actionKey: Key('currentMonthFixtures.reveal.$fixtureId'),
      icon: Icons.groups_rounded,
      label: l10n.fixturePredictionsButton,
      fill: fill,
      onTap: onTap,
    );
  }
}

/// An outlined action under a started card (script 119: actions): the way
/// to everyone's calls and, once the match is over, to its details.
class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.fill = false,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: label,
      // An InkWell, not a bare GestureDetector: on the web it takes keyboard
      // focus (Tab, then Enter) and shows the pointer hand (UI-25).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: actionKey,
          borderRadius: AppRadius.brButton,
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          // A 48 touch target around the 36px button (UI-16).
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Center(
              child: Container(
                // Wide enough to read as the card's one action under the
                // split (design of 2026-10-07), or the whole of its slot.
                constraints: BoxConstraints(
                  minHeight: _DoubleGlowButton._height,
                  minWidth: fill ? double.infinity : 200.0,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.brButton,
                  // A quiet tint, not a frame (script 128): two framed
                  // buttons under a finished card read heavier than its
                  // score. The label keeps the action blue.
                  color: tokens.primary.withValues(alpha: 0.10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: AppSizes.iconSm,
                      color: tokens.primaryText,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.s12,
                          color: tokens.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "make it double" toggle: a quiet outline by default (decided
/// 2026-10-07: a solid blue drew the eye before the teams), and once
/// selected a deeper blue gradient with a gold rim, a
/// filled white bolt and a soft glow. The bolt was gold until 2026-10-15:
/// 1.1:1 on the light theme's blue, 2.8:1 on the dark one, under the 3:1 an
/// icon needs; it now takes the label's white (6.7:1 and 4.5:1). The gradient runs from the action blue
/// DOWN, never up to the brighter blue: white on `primaryLight` is 3.6:1,
/// under WCAG AA for a 12px label. The state is never colour-alone -- the
/// rim and the icon change with it (accessibility). Reuses the same key the
/// prior chip design used (`currentMonthFixtures.double.$fixtureId`).
/// Since script 128 it takes its own width at the start of the card's
/// last row, and says when the day's double is on another match.
class _DoubleGlowButton extends StatelessWidget {
  const _DoubleGlowButton({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.fixtureId,
    this.takenElsewhere = false,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String fixtureId;

  /// Another match of the same Riyadh day holds the player's double: the
  /// toggle reads [_takenLabel] at full strength, so it can be read, and
  /// takes no tap.
  final bool takenElsewhere;

  static const String _takenLabel = 'مضاعفة اليوم مستخدمة';

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final String label = takenElsewhere
        ? _takenLabel
        : l10n.predictionMakeItDoubleLabel;

    return Opacity(
      opacity: enabled || takenElsewhere ? 1 : AppOpacity.disabled,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        // An InkWell, not a bare GestureDetector: on the web it takes
        // keyboard focus (Tab, then Enter) and shows the pointer hand (UI-25).
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('currentMonthFixtures.double.$fixtureId'),
            borderRadius: AppRadius.brButton,
            onTap: enabled
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    onTap();
                  }
                : null,
            // A 48 touch target around the 36px button (UI-16); the label
            // wraps at large text instead of being cut (UI-18).
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.minTouchTarget,
              ),
              // Its own width, not the row's (script 128).
              child: Align(
                widthFactor: 1,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  constraints: const BoxConstraints(minHeight: _height),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    // No alignment above: it stretched the toggle to the
                    // width it was given (script 128).
                    borderRadius: AppRadius.brButton,
                    color: selected ? null : Colors.transparent,
                    gradient: selected
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              tokens.primary,
                              Color.lerp(tokens.primary, Colors.black, 0.25)!,
                            ],
                          )
                        : null,
                    border: Border.all(
                      color: selected
                          ? tokens.goldAccent
                          : tokens.controlBorder,
                      width: selected ? 1.5 : AppStroke.hairline,
                    ),
                    boxShadow: selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: tokens.primary.withValues(alpha: 0.35),
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
                        color: selected
                            ? tokens.onPrimary
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: AppFontSize.s12,
                            color: selected
                                ? tokens.onPrimary
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a started match stands, for its header chip.
enum _MatchPhase {
  /// In play: a red "live" chip and the minute.
  live,

  /// Played (or past its live window) with no recorded result yet.
  awaitingResult,

  /// The result is recorded (or the call already graded).
  over,
}

/// The card after kickoff (design of 2026-10-07): the league and the live
/// chip with the minute, the two sides around the score in a box, the
/// player's own call between the two names, the split of everyone's calls
/// -- home win, draw, away win -- and the button to everyone's predictions.
///
/// Nothing here is computed: the score is the provider's running one or the
/// recorded result, the split comes from the server with the feed item.
class _StartedBody extends StatelessWidget {
  const _StartedBody({
    required this.item,
    required this.home,
    required this.away,
    required this.myPrediction,
    required this.isGraded,
    required this.grade,
    required this.points,
    required this.onOpenPredictions,
    this.onOpenDetails,
  });

  final CurrentMonthFixtureItemDto item;
  final ResolvedTeamIdentity home;
  final ResolvedTeamIdentity away;
  final FixturePredictionDto? myPrediction;
  final bool isGraded;
  final String? grade;
  final int? points;
  final VoidCallback onOpenPredictions;

  /// Opens the match details page; shown once the result is recorded.
  final VoidCallback? onOpenDetails;

  SeasonFixtureCardDto get _fixture => item.fixture;

  @override
  Widget build(BuildContext context) {
    final String fixtureId = _fixture.fixtureId;
    final bool recorded =
        item.resultHomeGoals != null && item.resultAwayGoals != null;
    final int? homeGoals = recorded ? item.resultHomeGoals : item.liveHomeGoals;
    final int? awayGoals = recorded ? item.resultAwayGoals : item.liveAwayGoals;
    final bool hasScore = homeGoals != null && awayGoals != null;
    // The result once it is recorded: the loser's name steps back and the
    // share of calls that got it right stays lit (script 119: outcome).
    final int? homeResult = item.resultHomeGoals;
    final int? awayResult = item.resultAwayGoals;
    final _Outcome? outcome = homeResult == null || awayResult == null
        ? null
        : homeResult > awayResult
        ? _Outcome.home
        : homeResult < awayResult
        ? _Outcome.away
        : _Outcome.draw;
    final _MatchPhase phase = recorded || isGraded
        ? _MatchPhase.over
        : hasScore
        ? ((item.liveFinished ?? false)
              ? _MatchPhase.awaitingResult
              : _MatchPhase.live)
        : (isFixtureLive(_fixture.kickoffAt)
              ? _MatchPhase.live
              : _MatchPhase.awaitingResult);

    // The split of everyone's calls: three-way from a server that sends
    // it, the two decisive shares from an older one; never over a handful
    // of calls (minShareSample).
    final int? total = item.totalPredictions;
    final int? decisive = item.decisivePredictions;
    final bool threeWay = total != null;
    final bool showShares = threeWay
        ? total >= minShareSample
        : item.homeWinPercentage != null &&
              (decisive == null || decisive >= minShareSample);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StartedHeader(
          competitionId: item.competitionId,
          competitionName: _fixture.leagueName ?? item.competitionName,
          leagueLogoUrl: _fixture.leagueLogoUrl,
          phase: phase,
          minute: phase == _MatchPhase.live ? item.liveMinute : null,
          fixtureId: fixtureId,
        ),
        const SizedBox(height: AppSpacing.md),
        _ScoreRow(
          fixtureId: fixtureId,
          home: home,
          away: away,
          homeGoals: homeGoals,
          awayGoals: awayGoals,
          // script 119: the loser steps back.
          outcome: outcome,
        ),
        // A live match whose feed carries no running score: a lone dash
        // did not say whether it was goalless or the score was not
        // coming (2026-10-19).
        if (phase == _MatchPhase.live && !hasScore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'لا تتوفر نتيجة مباشرة حتى الآن',
              key: Key('currentMonthFixtures.liveNoScore.$fixtureId'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.s12,
                fontWeight: FontWeight.w600,
                color: context.tokens.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _CallStrip(
          fixtureId: fixtureId,
          prediction: myPrediction,
          grade: isGraded ? grade : null,
          points: isGraded ? points : null,
        ),
        if (showShares) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _OutcomeShares(
            key: Key('currentMonthFixtures.outcomeShares.$fixtureId'),
            home: threeWay
                ? (item.homeOutcomeShare ?? 0)
                : (item.homeWinPercentage ?? 0),
            draw: threeWay ? (item.drawOutcomeShare ?? 0) : null,
            away: threeWay
                ? (item.awayOutcomeShare ?? 0)
                : (item.awayWinPercentage ?? 0),
            homeName: home.displayName,
            awayName: away.displayName,
            // script 119: the share that called the result stays lit.
            actual: outcome,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        // script 119: once the match is over the two ways out share one
        // row; each half wraps its own label at large text.
        if (recorded && onOpenDetails != null)
          Row(
            children: <Widget>[
              Expanded(
                child: _RevealPredictionsButton(
                  fixtureId: fixtureId,
                  onTap: onOpenPredictions,
                  fill: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OutlinedAction(
                  actionKey: Key('currentMonthFixtures.details.$fixtureId'),
                  icon: Icons.timeline_rounded,
                  label: 'تفاصيل المباراة',
                  fill: true,
                  onTap: onOpenDetails!,
                ),
              ),
            ],
          )
        else
          Center(
            child: _RevealPredictionsButton(
              fixtureId: fixtureId,
              onTap: onOpenPredictions,
            ),
          ),
      ],
    );
  }
}

/// The started card's header: the league on the leading side, the match
/// status (and, while live, the minute) on the trailing side.
class _StartedHeader extends StatelessWidget {
  const _StartedHeader({
    required this.competitionId,
    required this.competitionName,
    required this.leagueLogoUrl,
    required this.phase,
    required this.minute,
    required this.fixtureId,
  });

  final String competitionId;
  final String competitionName;
  final String? leagueLogoUrl;
  final _MatchPhase phase;
  final int? minute;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool live = phase == _MatchPhase.live;
    final String label = switch (phase) {
      _MatchPhase.live => l10n.fixturesLiveLabel,
      _MatchPhase.awaitingResult => l10n.predictionPendingResultLabel,
      _MatchPhase.over => 'انتهت',
    };
    final int? clock = minute;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => _row(
        context,
        width: constraints.maxWidth,
        label: label,
        live: live,
        clock: clock,
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required double width,
    required String label,
    required bool live,
    required int? clock,
  }) {
    final tokens = context.tokens;
    return Row(
      children: <Widget>[
        _CompetitionLogo(
          assetPath: competitionLogoAsset(competitionId, competitionName),
          logoUrl: leagueLogoUrl,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            competitionName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.s13,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (clock != null) ...<Widget>[
          Text(
            "$clock'",
            key: Key('currentMonthFixtures.liveMinute.$fixtureId'),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: AppFontSize.s16,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        // At most half the header, so a long status ("result pending")
        // at large text ends in an ellipsis instead of overflowing.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width / 2),
          child: Container(
            key: Key('currentMonthFixtures.liveStatus.$fixtureId'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: live ? tokens.errorContainer : tokens.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.s13,
                      fontWeight: FontWeight.w700,
                      color: live ? tokens.errorText : tokens.textSecondary,
                    ),
                  ),
                ),
                if (live) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  // Steady, never pulsing: an animation here would repaint
                  // the whole screen every frame of the match.
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One side of a started match: its name and crest in a line, the crest
/// toward the score. [crestFirst] puts the crest first in reading order
/// (the second side, whose crest sits next to the score box).
class _StartedSide extends StatelessWidget {
  const _StartedSide({
    required this.fixtureId,
    required this.team,
    required this.crestFirst,
    this.dimmed = false,
  });

  final String fixtureId;
  final ResolvedTeamIdentity team;
  final bool crestFirst;

  /// The losing side once the result is in: its name steps back (script
  /// 119: dimmed).
  final bool dimmed;

  static const double _crestSize = 34;

  /// The narrowest a side may be: its crest, the gap and room for the
  /// start of the name.
  static const double minWidth = _crestSize + AppSpacing.sm + AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Widget crest = TeamLogo(
      displayName: team.displayName,
      crestUrl: team.crestUrl,
      assetPath: team.assetPath,
      brandColor: team.brandColor,
      size: _crestSize,
    );
    final Widget name = Flexible(
      child: Text(
        team.displayName,
        key: Key(
          'currentMonthFixtures.side.$fixtureId.${crestFirst ? 'away' : 'home'}',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: crestFirst ? TextAlign.start : TextAlign.end,
        style: TextStyle(
          fontSize: AppFontSize.s15,
          fontWeight: FontWeight.w700,
          color: dimmed ? tokens.textSecondary : tokens.textPrimary,
        ),
      ),
    );
    return Row(
      mainAxisAlignment: crestFirst
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: crestFirst
          ? <Widget>[crest, const SizedBox(width: AppSpacing.sm), name]
          : <Widget>[name, const SizedBox(width: AppSpacing.sm), crest],
    );
  }
}

/// The two sides around the score. At large text the framed score would
/// leave the sides no room for their crests (UI audit, text scale x2.0),
/// so the score drops under the sides instead of overflowing them.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.fixtureId,
    required this.home,
    required this.away,
    required this.homeGoals,
    required this.awayGoals,
    this.outcome,
  });

  final String fixtureId;
  final ResolvedTeamIdentity home;
  final ResolvedTeamIdentity away;
  final int? homeGoals;
  final int? awayGoals;

  /// The recorded result's side, null until then (script 119: row).
  final _Outcome? outcome;

  @override
  Widget build(BuildContext context) {
    final Widget score = _ScoreBox(
      fixtureId: fixtureId,
      home: homeGoals,
      away: awayGoals,
    );
    // script 119: sides; the loser's name steps back once the result is in.
    final Widget homeSide = _StartedSide(
      fixtureId: fixtureId,
      team: home,
      crestFirst: false,
      dimmed: outcome == _Outcome.away,
    );
    final Widget awaySide = _StartedSide(
      fixtureId: fixtureId,
      team: away,
      crestFirst: true,
      dimmed: outcome == _Outcome.home,
    );
    final double inline =
        _ScoreBox.widthOf(context, homeGoals, awayGoals) +
        2 * AppSpacing.sm +
        2 * _StartedSide.minWidth;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (inline <= constraints.maxWidth) {
          return Row(
            children: <Widget>[
              Expanded(child: homeSide),
              const SizedBox(width: AppSpacing.sm),
              score,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: awaySide),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: homeSide),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: awaySide),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(child: score),
          ],
        );
      },
    );
  }
}

/// The score between the two sides, in a framed box: the running score
/// while live, the recorded one once over, a dash before the first update.
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.fixtureId, this.home, this.away});

  final String fixtureId;
  final int? home;
  final int? away;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.xs,
  );

  static String _label(BuildContext context, int? home, int? away) =>
      home != null && away != null
      ? orientedScoreLabel(context, home, away)
      : '-';

  static TextStyle _style(BuildContext context) => TextStyle(
    fontSize: AppFontSize.s26,
    fontWeight: FontWeight.w800,
    color: context.tokens.textPrimary,
    height: 1.2,
  );

  /// The box's width at the reader's text size: the score as it will be
  /// laid out, its padding and the frame on both sides.
  static double widthOf(BuildContext context, int? home, int? away) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: _label(context, home, away),
        style: DefaultTextStyle.of(context).style.merge(_style(context)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width + _padding.horizontal + 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bool known = home != null && away != null;
    return Container(
      key: known ? Key('currentMonthFixtures.liveScore.$fixtureId') : null,
      padding: _padding,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brButton,
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        _label(context, home, away),
        textDirection: TextDirection.ltr,
        style: _style(context),
      ),
    );
  }
}

/// The player's own call under the score. Before the grade, "your call
/// 2 - 1" (a bolt on the day's double) in a framed strip; without a call,
/// the strip says so. Once graded, the strip leads with the points -- the
/// one number a player comes back for, the largest on the strip (script
/// 128) -- then the verdict in the history's words and the call, on a fill
/// that follows the verdict: green for the exact score, gold for an exact
/// double, red for a miss, neutral otherwise. The words say it too, so the
/// colour is never alone. The points are the server's, never recomputed.
class _CallStrip extends StatelessWidget {
  const _CallStrip({
    required this.fixtureId,
    required this.prediction,
    required this.grade,
    required this.points,
  });

  final String fixtureId;
  final FixturePredictionDto? prediction;
  final String? grade;
  final int? points;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final TextStyle labelStyle = TextStyle(
      fontSize: AppFontSize.s12,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );
    final BoxDecoration frame = BoxDecoration(
      borderRadius: AppRadius.brButton,
      border: Border.all(color: tokens.border),
    );
    const EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    );
    final FixturePredictionDto? call = prediction;
    if (call == null) {
      return Container(
        padding: padding,
        decoration: frame,
        child: Text(
          'لم تتوقّع',
          textAlign: TextAlign.center,
          style: labelStyle,
        ),
      );
    }
    final int? earned = points;
    // A Wrap: at large text the score drops under "your call" instead of
    // squeezing it.
    final Widget callLine = Wrap(
      key: Key('currentMonthFixtures.myCall.$fixtureId'),
      alignment: earned == null ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        Text(l10n.matchCardYourCall, style: labelStyle),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              orientedScoreLabel(context, call.homeGoals, call.awayGoals),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: AppFontSize.s16,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            if (call.isDouble) ...<Widget>[
              const SizedBox(width: 2),
              Icon(
                Icons.bolt_rounded,
                size: AppSizes.iconInline,
                color: tokens.gold,
              ),
            ],
          ],
        ),
      ],
    );
    if (earned == null) {
      return Container(padding: padding, decoration: frame, child: callLine);
    }
    final bool scored = earned > 0;
    final ({String words, Color figure, Color fill}) tone = switch (grade) {
      'exact_scoreline' when call.isDouble => (
        words: l10n.historyGradeExact,
        figure: tokens.gold,
        fill: tokens.goldContainer,
      ),
      'exact_scoreline' => (
        words: l10n.historyGradeExact,
        figure: tokens.successText,
        fill: tokens.successContainer,
      ),
      'incorrect' => (
        words: l10n.historyGradeWrong,
        figure: tokens.errorText,
        fill: tokens.errorContainer,
      ),
      'correct_outcome' => (
        words: l10n.historyGradeOutcome,
        figure: scored ? tokens.successText : tokens.textPrimary,
        fill: scored ? tokens.successContainer : tokens.surfaceHigh,
      ),
      _ => (
        words: '',
        figure: scored ? tokens.successText : tokens.textPrimary,
        fill: scored ? tokens.successContainer : tokens.surfaceHigh,
      ),
    };
    return Container(
      key: Key('currentMonthFixtures.verdict.$fixtureId'),
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: AppRadius.brButton,
        color: tone.fill,
      ),
      // A Wrap, not a Row: at large text the words and the call drop under
      // the points. Beside them they were left too little width, and the
      // call's score overflowed it by 135px at text x2.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          Text(
            l10n.pointsAbbreviated(earned),
            key: Key('currentMonthFixtures.points.$fixtureId'),
            style: TextStyle(
              fontSize: AppFontSize.s20,
              fontWeight: FontWeight.w800,
              color: tone.figure,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (tone.words.isNotEmpty)
                Text(
                  tone.words,
                  style: TextStyle(
                    fontSize: AppFontSize.s13,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              callLine,
            ],
          ),
        ],
      ),
    );
  }
}

/// The split of everyone's calls under a caption that says so (script
/// 119: shares): the home win share with its bar, the draw share in the
/// middle, the away win share with its bar, all in one neutral colour.
/// Once the result is in ([actual]) the share that called it turns green
/// and the other two step back. A [draw] of null (an older server)
/// leaves the middle empty and the two shares are the decisive ones.
class _OutcomeShares extends StatelessWidget {
  const _OutcomeShares({
    super.key,
    required this.home,
    required this.draw,
    required this.away,
    required this.homeName,
    required this.awayName,
    this.actual,
  });

  final int home;
  final int? draw;
  final int away;
  final String homeName;
  final String awayName;
  final _Outcome? actual;

  static const String _caption = 'كيف توقّع اللاعبون';
  static const String _winLabel = 'فوز';
  static const String _drawLabel = 'التعادل';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final int? drawShare = draw;
    final _Outcome? result = actual;
    // Green and red for the two sides read as right and wrong before
    // anything was decided (2026-10-19): one neutral colour until the
    // result is in, then green for the share that called it.
    Color figure(_Outcome side) => result == null
        ? tokens.textPrimary
        : result == side
        ? tokens.successText
        : tokens.textSecondary;
    Color bar(_Outcome side) => result == null
        ? tokens.primary
        : result == side
        ? tokens.success
        : tokens.textPrimary.withValues(alpha: AppOpacity.statusBorder);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppFontSize.s12,
            fontWeight: FontWeight.w600,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Each side's share over its team's name, not "win" twice
        // (script 131): the two wins read the same. The names take the
        // room the bars gave up; the voice still says "win".
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 6,
              child: _ShareFigure(
                percentage: home,
                label: homeName,
                color: figure(_Outcome.home),
                spoken: '$_winLabel $homeName $home%',
              ),
            ),
            // script 132: bar flex home -- the names beside the figures
            // take the room.
            Expanded(
              flex: 2,
              child: _ShareBar(
                fraction: home / 100,
                color: bar(_Outcome.home),
                fromStart: true,
              ),
            ),
            Expanded(
              flex: 6,
              child: drawShare == null
                  ? const SizedBox.shrink()
                  : _ShareFigure(
                      percentage: drawShare,
                      label: _drawLabel,
                      color: figure(_Outcome.draw),
                      spoken: '$_drawLabel $drawShare%',
                    ),
            ),
            // script 132: bar flex away.
            Expanded(
              flex: 2,
              child: _ShareBar(
                fraction: away / 100,
                color: bar(_Outcome.away),
                fromStart: false,
              ),
            ),
            Expanded(
              flex: 6,
              child: _ShareFigure(
                percentage: away,
                label: awayName,
                color: figure(_Outcome.away),
                spoken: '$_winLabel $awayName $away%',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the open card shows instead of the split until [minShareSample]
/// calls are in: the caption, and a line that says when the shares will
/// show (2026-10-19).
class _SharesPending extends StatelessWidget {
  const _SharesPending({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _OutcomeShares._caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.s12,
            fontWeight: FontWeight.w600,
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'تظهر نسب الجمهور بعد $minShareSample توقعات',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.s13,
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Which side a recorded result went to (script 119: outcome enum).
enum _Outcome { home, draw, away }

/// One share: the figure beside its label, on one line
/// (script 132: one-line share -- two lines made the card taller than the
/// FotMob one).
/// At large text the figure scales down inside its cell rather than
/// overflowing it, and the label ends in an ellipsis.
class _ShareFigure extends StatelessWidget {
  const _ShareFigure({
    required this.percentage,
    required this.label,
    required this.color,
    required this.spoken,
  });

  final int percentage;
  final String label;
  final Color color;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ConstrainedBox(
              // figureCap: 0.6 of the cell, the rest for the label.
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth.isFinite
                    ? constraints.maxWidth * 0.6
                    : double.infinity,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$percentage%',
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: AppFontSize.s16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.s12,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A share as a bar: a quiet track filled to [fraction], from the side of
/// its figure ([fromStart] for the home side).
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.fraction,
    required this.color,
    required this.fromStart,
  });

  final double fraction;
  final Color color;
  final bool fromStart;

  static const double _height = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color: tokens.textPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(_height / 2),
        ),
        alignment: fromStart
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: FractionallySizedBox(
          widthFactor: fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(_height / 2),
            ),
          ),
        ),
      ),
    );
  }
}
