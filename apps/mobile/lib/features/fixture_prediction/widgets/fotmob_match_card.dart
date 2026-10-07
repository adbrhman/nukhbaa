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
// intl is already a transitive dependency (pulled in by the SDK's
// flutter_localizations, the same package the generated l10n files import
// it from — see their own `// ignore_for_file: type=lint`); not declared
// directly in pubspec.yaml, and the task's "no new dependencies" rule
// means it should not be added there just to silence this lint.
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_typography.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_opacity.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_stroke.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/error/error_presenter.dart';
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
import '../../history/fixture_scores_providers.dart';
import '../../history/prediction_history_providers.dart';
import '../../history/prediction_lookup_providers.dart';
import '../../leaderboards/season_leaderboard_screen.dart';
import '../../notifications/favorite_team_offer.dart';
import '../feed_refresh_signal.dart';
import '../fixture_prediction_controller.dart';
import '../fixture_prediction_submission.dart';
import 'fixture_predictions_board_page.dart';
import 'live_matches_chip.dart';

/// Fewest decisive predictions a win share is shown for: over one call a
/// share read "100%", a verdict it is not (decided 2026-10-07).
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
  /// The reschedule covers two legitimate races -- a submit already in flight,
  /// and a server that ended up holding values older than the ones on screen
  /// -- and both settle within a round or two. Unbounded, a disagreement that
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

    if (ref.read(fixturePredictionControllerProvider(_key))
        is FixtureSubmissionInFlight) {
      _scheduleAutoSave(isRetry: true);
      return;
    }

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

    // PERF: a fixture that has not kicked off cannot have been graded, so
    // asking the server for its scores is a guaranteed-empty round trip --
    // one per visible card, on a screen that is mostly upcoming matches.
    final AsyncValue<FixtureScoresDto>? scoresAsync =
        myPrediction == null || !locked
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

    final bool showEditableControls = !locked && !isGraded;
    // Interactivity must NOT depend on an in-flight submit. The auto-save is
    // debounced at 250 ms, and the pause while moving a finger from one
    // stepper to the other is longer than that -- so the save fired and
    // disabled all four +/- zones plus the double toggle for the whole
    // request, making the second side look dead to fast taps. The controller
    // already ignores an overlapping submit and _saveLatestPrediction
    // reschedules itself until the server holds the current value, so the
    // last tap still wins.
    final bool enabled = !locked;
    // The win shares arrive with the feed item itself. They used to be a
    // separate GET per card, so a twenty-match day opened twenty extra
    // requests over a phone network to learn twenty numbers the feed's own
    // query already had in hand. `null` means the server did not send them
    // (an older build); nobody having predicted is a real 0.
    final int homeWinShare = widget.item.homeWinPercentage ?? 0;
    final int awayWinShare = widget.item.awayWinPercentage ?? 0;
    // An older server sends no count, and the shares show as before.
    final int? decisive = widget.item.decisivePredictions;
    final bool showShares = decisive == null || decisive >= minShareSample;
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
                // A test fixture reaches admins only (migration 0098);
                // the label keeps it from passing for a real match.
                if (_fixture.isTest) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppBadge(
                      key: Key('currentMonthFixtures.testBadge'),
                      label: 'مباراة تجريبية',
                      tone: AppBadgeTone.gold,
                      icon: Icons.science_outlined,
                    ),
                  ),
                ],
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
                    ListenableBuilder(
                      listenable: Listenable.merge(<Listenable>[
                        _homeGoals,
                        _awayGoals,
                      ]),
                      builder: (context, _) {
                        final int? homeGoals = _homeGoals.value;
                        final int? awayGoals = _awayGoals.value;
                        return _MiddleSlot(
                          isGraded: isGraded,
                          locked: locked,
                          live: locked && isFixtureLive(_fixture.kickoffAt),
                          liveHome: widget.item.liveHomeGoals,
                          liveAway: widget.item.liveAwayGoals,
                          liveMinute: widget.item.liveMinute,
                          liveFinished: widget.item.liveFinished,
                          resultHome: widget.item.resultHomeGoals,
                          resultAway: widget.item.resultAwayGoals,
                          myPrediction: myPrediction,
                          grade: myGrade,
                          points: myPoints,
                          homeGoals: homeGoals,
                          awayGoals: awayGoals,
                          enabled: enabled,
                          showEditableControls: showEditableControls,
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
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: showShares
                            ? _WinPercentage(
                                percentage: homeWinShare,
                                teamName: home.displayName,
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (showEditableControls)
                        SizedBox(
                          width: 130,
                          child: _DoubleGlowButton(
                            selected: _isDouble,
                            enabled: enabled,
                            onTap: _toggleDouble,
                            fixtureId: fixtureId,
                          ),
                        )
                      // After kickoff the double button's slot opens the
                      // day's predictions table (the server reveals each
                      // match only from its kickoff, when predicting closes).
                      else if (locked)
                        SizedBox(
                          width: 130,
                          child: _RevealPredictionsButton(
                            fixtureId: fixtureId,
                            onTap: () => unawaited(
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FixturePredictionsBoardPage(
                                    kickoffAt: _fixture.kickoffAt,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(
                          width: 130,
                          height: AppSizes.minTouchTarget,
                        ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: showShares
                            ? _WinPercentage(
                                percentage: awayWinShare,
                                teamName: away.displayName,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                if (!locked && myPrediction != null)
                  ListenableBuilder(
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
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: TextButton.icon(
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
                            AppLocalizations.of(context).shareHitShareButton,
                          ),
                        ),
                      );
                    },
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
                              color: tokens.error,
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
                    fontSize: AppFontSize.s12,
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
                        fontSize: AppFontSize.s13,
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
    this.liveHome,
    this.liveAway,
    this.liveMinute,
    this.liveFinished,
    this.resultHome,
    this.resultAway,
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

  /// The provider's running score for a locked card (display only).
  final int? liveHome;
  final int? liveAway;
  final int? liveMinute;
  final bool? liveFinished;

  /// The recorded final score, once there is one (the feed's).
  final int? resultHome;
  final int? resultAway;

  @override
  Widget build(BuildContext context) {
    if (isGraded && myPrediction != null) {
      return _GradedSlot(
        prediction: myPrediction!,
        grade: grade,
        points: points,
        fixtureId: fixtureId,
        resultHome: resultHome,
        resultAway: resultAway,
      );
    }
    if (locked) {
      return _LockedSlot(
        live: live,
        fixtureId: fixtureId,
        myPrediction: myPrediction,
        home: liveHome,
        away: liveAway,
        minute: liveMinute,
        finished: liveFinished,
        resultHome: resultHome,
        resultAway: resultAway,
      );
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

class _GradedSlot extends StatelessWidget {
  const _GradedSlot({
    required this.prediction,
    required this.grade,
    required this.points,
    required this.fixtureId,
    this.resultHome,
    this.resultAway,
  });

  final FixturePredictionDto prediction;
  final String? grade;
  final int? points;
  final String fixtureId;

  /// The recorded final score, when the feed carries it.
  final int? resultHome;
  final int? resultAway;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    // Tone follows the server's points, not the grade name: a correct
    // outcome can award 0 under the frozen ruleset, and a green "0 pts"
    // reads as a win nobody got.
    final bool success = (points ?? 0) > 0;
    final int? home = resultHome;
    final int? away = resultAway;
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
        // The final score beside the call: without it the points said
        // nothing about why (decided 2026-10-07).
        if (home != null && away != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'النتيجة ${orientedScoreLabel(context, home, away)}',
            key: Key('currentMonthFixtures.finalScore.$fixtureId'),
            maxLines: 1,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: AppFontSize.s12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// A started, not-yet-graded fixture: "live" (red dot) inside the
/// [liveWindow] after kickoff, then "awaiting result" -- instead of one
/// generic "started" label for both, which kept a finished match looking
/// like it was still being played.
class _LockedSlot extends StatelessWidget {
  const _LockedSlot({
    required this.live,
    required this.fixtureId,
    this.myPrediction,
    this.home,
    this.away,
    this.minute,
    this.finished,
    this.resultHome,
    this.resultAway,
  });

  final bool live;
  final String fixtureId;

  /// The provider's running (or, when [finished], final) score, if any.
  final int? home;
  final int? away;
  final int? minute;
  final bool? finished;

  /// The recorded final score: once there is one the match is over,
  /// whatever the provider last said.
  final int? resultHome;
  final int? resultAway;

  /// The player's own call, shown under the status once kickoff has hidden
  /// the steppers; null when they did not predict this match.
  final FixturePredictionDto? myPrediction;

  @override
  Widget build(BuildContext context) {
    final Widget status = _status(context);
    final FixturePredictionDto? mine = myPrediction;
    if (mine == null) return status;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        status,
        const SizedBox(height: AppSpacing.xs),
        _MyCallLine(prediction: mine, fixtureId: fixtureId),
      ],
    );
  }

  Widget _status(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool recorded = resultHome != null && resultAway != null;
    final int? homeGoals = recorded ? resultHome : home;
    final int? awayGoals = recorded ? resultAway : away;
    if (homeGoals != null && awayGoals != null) {
      final bool over = recorded || (finished ?? false);
      final Color accent = over ? tokens.textMuted : tokens.error;
      // The dot keeps the danger red; the words take the red made for text.
      final Color accentText = over ? tokens.textMuted : tokens.errorText;
      final int? clock = minute;
      return Column(
        key: Key('currentMonthFixtures.liveScore.$fixtureId'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            orientedScoreLabel(context, homeGoals, awayGoals),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: AppFontSize.s26,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!over) ...<Widget>[
                Icon(Icons.circle, size: 8, color: accent),
                const SizedBox(width: 4),
              ],
              Text(
                recorded
                    ? 'انتهت'
                    : over
                    ? l10n.predictionPendingResultLabel
                    : clock != null
                    ? "$clock'"
                    : l10n.fixturesLiveLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: over || clock == null ? null : TextDirection.ltr,
                style: TextStyle(color: accentText, fontSize: AppFontSize.s11),
              ),
            ],
          ),
        ],
      );
    }
    final Color color = live ? tokens.error : tokens.textMuted;
    final Color textColor = live ? tokens.errorText : tokens.textMuted;
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
          style: TextStyle(color: textColor, fontSize: AppFontSize.s11),
        ),
      ],
    );
  }
}

/// "Your call 2 - 1" under a started match. Once kickoff hid the steppers
/// the card no longer said what the player had called -- right when they
/// were following the score. A bolt marks the day's double.
class _MyCallLine extends StatelessWidget {
  const _MyCallLine({required this.prediction, required this.fixtureId});

  final FixturePredictionDto prediction;
  final String fixtureId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final TextStyle style = TextStyle(
      color: tokens.textSecondary,
      fontSize: AppFontSize.s11,
      fontWeight: FontWeight.w600,
    );
    return Row(
      key: Key('currentMonthFixtures.myCall.$fixtureId'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(l10n.matchCardYourCall, style: style),
        const SizedBox(width: 4),
        Text(
          orientedScoreLabel(
            context,
            prediction.homeGoals,
            prediction.awayGoals,
          ),
          textDirection: TextDirection.ltr,
          style: style.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (prediction.isDouble) ...<Widget>[
          const SizedBox(width: 2),
          Icon(
            Icons.bolt_rounded,
            size: AppSizes.iconInline,
            color: tokens.gold,
          ),
        ],
      ],
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

class _WinPercentage extends StatelessWidget {
  const _WinPercentage({required this.percentage, required this.teamName});

  final int percentage;

  /// Spoken with the share: "86%" alone did not say whose win (UI-28).
  final String teamName;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // A figure, not a control: plain text with no frame, so it no longer
    // reads as two buttons that do nothing (UI-28). It wraps at large text
    // instead of shrinking inside a FittedBox (UI-17).
    return Semantics(
      label: '\u0641\u0648\u0632 $teamName $percentage%',
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _DoubleGlowButton._height,
          ),
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              children: <Widget>[
                Text(
                  '$percentage%',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: AppFontSize.s16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '\u0641\u0648\u0632',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: AppFontSize.s13,
                    fontWeight: FontWeight.w600,
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

/// The started card's "everyone's predictions" button, drawn in the slot
/// and at the height of [_DoubleGlowButton] so the card keeps its layout.
class _RevealPredictionsButton extends StatelessWidget {
  const _RevealPredictionsButton({
    required this.fixtureId,
    required this.onTap,
  });

  final String fixtureId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final String label = l10n.fixturePredictionsButton;
    return Semantics(
      button: true,
      label: label,
      // An InkWell, not a bare GestureDetector: on the web it takes keyboard
      // focus (Tab, then Enter) and shows the pointer hand (UI-25).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('currentMonthFixtures.reveal.$fixtureId'),
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
                constraints: const BoxConstraints(
                  minHeight: _DoubleGlowButton._height,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.brButton,
                  border: Border.all(color: tokens.primary),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.groups_rounded,
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
/// filled gold bolt and a soft glow. The gradient runs from the action blue
/// DOWN, never up to the brighter blue: white on `primaryLight` is 3.6:1,
/// under WCAG AA for a 12px label. The state is never colour-alone -- the
/// rim and the icon change with it (accessibility). Reuses the same key the
/// prior chip design used (`currentMonthFixtures.double.$fixtureId`).
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
              child: Center(
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  constraints: const BoxConstraints(minHeight: _height),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
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
                      color: selected ? tokens.gold : tokens.controlBorder,
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
                        color: selected ? tokens.gold : tokens.textSecondary,
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
