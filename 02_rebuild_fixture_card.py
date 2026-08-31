import pathlib

root = pathlib.Path(".")

# ---------------------------------------------------------------------------
# 1) current_month_fixtures_screen.dart — استبدال كتلة الاستيراد + إعادة بناء
#    _CurrentMonthFixtureCard بالكامل (مدمجة/موسّعة + شعارات + 1/X/2 + Stepper
#    + شارة الدبل + حالة "تم التوقع/النتيجة" + العدّاد المعزول من سكربت 01).
# ---------------------------------------------------------------------------
screen_path = root / "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart"
screen_text = screen_path.read_text(encoding="utf-8")

old_imports = """import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../l10n/app_localizations.dart';
import '../leaderboards/season_leaderboard_screen.dart';
import 'current_month_fixtures_providers.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_submission.dart';"""

new_imports = """import '../../core/design/app_motion.dart';
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
import '../leaderboards/season_leaderboard_screen.dart';
import 'current_month_fixtures_providers.dart';
import 'fixture_prediction_controller.dart';
import 'fixture_prediction_submission.dart';
import 'kickoff_countdown.dart';"""

assert screen_text.count(old_imports) == 1, "كتلة الاستيراد القديمة غير فريدة أو غير موجودة"
screen_text = screen_text.replace(old_imports, new_imports, 1)

old_tail_marker = "/// One fixture's card: owning competition label, team names, kickoff, a"
assert screen_text.count(old_tail_marker) == 1, "علامة بداية _CurrentMonthFixtureCard القديمة غير فريدة"
old_tail_start = screen_text.index(old_tail_marker)
old_tail = screen_text[old_tail_start:]
assert old_tail.endswith("}\n"), "الجزء المراد استبداله لا ينتهي بنهاية الملف كما هو متوقع"

new_tail = '''/// One fixture's card: owning competition label, team crests/names, a
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
    ref.listen<FixtureSubmissionState>(fixturePredictionControllerProvider(_key), (
      previous,
      next,
    ) {
      if (next is FixtureSubmissionSucceeded) {
        ref.invalidate(myFixturePredictionsProvider);
      }
    });

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
                subm
