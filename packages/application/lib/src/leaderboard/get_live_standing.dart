import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/ruleset_provider.dart';
import 'package:application/src/football_data/ports/live_score_board.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/fixture_totals_reader.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/social/duel_views.dart';
import 'package:application/src/social/ports/duel_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One match of the season in play, as the viewer stands in it.
final class LiveFixtureStanding {
  /// Creates the line.
  const LiveFixtureStanding({
    required this.fixture,
    required this.homeGoals,
    required this.awayGoals,
    required this.minute,
    required this.finished,
    required this.myPoints,
  });

  /// The match.
  final FixtureRef fixture;

  /// The running score.
  final int homeGoals;

  /// The running score.
  final int awayGoals;

  /// The match minute, when the provider reports one.
  final int? minute;

  /// The provider says it is over; its result is not recorded yet.
  final bool finished;

  /// What the viewer's prediction would earn if the match ended now; null
  /// when they did not predict it.
  final int? myPoints;
}

/// One of the viewer's duels on a match in play.
final class LiveDuelStanding {
  /// Creates the line.
  const LiveDuelStanding({
    required this.fixture,
    required this.opponentName,
    required this.myPoints,
    required this.opponentPoints,
  });

  /// The match.
  final FixtureRef fixture;

  /// The other player.
  final String opponentName;

  /// What the viewer would earn if the match ended now.
  final int myPoints;

  /// What the other player would earn.
  final int opponentPoints;
}

/// Where the viewer stands while the season's matches are in play.
final class LiveStanding {
  /// Creates the standing.
  const LiveStanding({
    required this.fixtures,
    required this.duels,
    required this.rankNow,
    required this.rankIfEnded,
    required this.pointsNow,
    required this.pointsIfEnded,
    required this.players,
  });

  /// Nothing in play.
  static const LiveStanding none = LiveStanding(
    fixtures: <LiveFixtureStanding>[],
    duels: <LiveDuelStanding>[],
    rankNow: null,
    rankIfEnded: null,
    pointsNow: 0,
    pointsIfEnded: 0,
    players: 0,
  );

  /// The season's matches in play, in the season's order.
  final List<LiveFixtureStanding> fixtures;

  /// The viewer's duels on them.
  final List<LiveDuelStanding> duels;

  /// The viewer's place on the month board now; null when not on it.
  final int? rankNow;

  /// Their place if every match in play ended at its running score.
  final int? rankIfEnded;

  /// Their points now.
  final int pointsNow;

  /// Their points if every match in play ended now.
  final int pointsIfEnded;

  /// Players on the board if every match in play ended now.
  final int players;
}

/// Query use-case: while a season's matches are in play, what the viewer's
/// predictions would earn if they ended now, their place on the month board
/// now and then, and who leads each of their duels on them (phase 5 of the
/// plan: the match is live inside the app).
///
/// Points are graded here, on the server, by the same rules as a recorded
/// result ([Scoring.gradeScoreline]) against the running score the provider
/// reported ([LiveScoreBoard]); nothing is stored and nothing changes the
/// board. A match whose result is already recorded is left out: the board
/// counts it. The month board is ranked as `GetSeasonFixtureLeaderboard`
/// ranks it.
///
/// Only a member of the season reads it, refused otherwise as
/// [ErrorKind.authorization] `leaderboard.not_a_participant`. Never throws;
/// returns a typed [Result].
final class GetLiveStanding {
  /// Creates the use-case over its collaborators. [liveScores] is null when
  /// no provider reports running scores: nothing is ever in play then.
  const GetLiveStanding({
    required CompetitionRepository competition,
    required FixturePredictionRepository fixturePredictions,
    required FixtureTotalsReader totals,
    required FixtureResultRepository results,
    required RulesetProvider rulesets,
    required DuelReader duels,
    required LiveScoreBoard? liveScores,
    required Clock clock,
  }) : _competition = competition,
       _fixturePredictions = fixturePredictions,
       _totals = totals,
       _results = results,
       _rulesets = rulesets,
       _duels = duels,
       _liveScores = liveScores,
       _clock = clock;

  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureTotalsReader _totals;
  final FixtureResultRepository _results;
  final RulesetProvider _rulesets;
  final DuelReader _duels;
  final LiveScoreBoard? _liveScores;
  final Clock _clock;

  /// How far back the viewer's duels are read: a match in play kicked off
  /// within the last day.
  static const Duration duelWindow = Duration(days: 1);

  /// The viewer's live standing in [seasonId].
  Future<Result<LiveStanding>> call({
    required AuthenticatedUser principal,
    required String seasonId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) {
      return Result.err(seasonResult.error);
    }
    final SeasonId season = (seasonResult as Ok<SeasonId>).value;
    final member = await _competition.findParticipant(season, principal.userId);
    if (member is Err<Participant?>) {
      return Result.err(member.error);
    }
    final Participant? me = (member as Ok<Participant?>).value;
    if (me == null) {
      return const Result.err(
        AppError.authorization(
          'leaderboard.not_a_participant',
          'Only a member of the season may view its leaderboard',
        ),
      );
    }
    final LiveScoreBoard? board = _liveScores;
    if (board == null) return const Result.ok(LiveStanding.none);

    final fixturesResult = await _fixturePredictions.listSeasonFixtures(season);
    if (fixturesResult is Err<List<FixtureRef>>) {
      return Result.err(fixturesResult.error);
    }
    final List<FixtureRef> fixtures =
        (fixturesResult as Ok<List<FixtureRef>>).value;
    final Map<String, LiveScore> running = board.read(<String>[
      for (final FixtureRef f in fixtures) f.value,
    ]);
    if (running.isEmpty) return const Result.ok(LiveStanding.none);

    // A recorded result is on the board already: never count it twice.
    final List<FixtureRef> candidates = <FixtureRef>[
      for (final FixtureRef f in fixtures)
        if (running.containsKey(f.value)) f,
    ];
    final recorded = await _results.findByFixtures(candidates);
    if (recorded is Err<List<FixtureResult>>) {
      return Result.err(recorded.error);
    }
    final Set<String> done = <String>{
      for (final FixtureResult r in (recorded as Ok<List<FixtureResult>>).value)
        r.fixture.value,
    };
    final List<FixtureRef> inPlay = <FixtureRef>[
      for (final FixtureRef f in candidates)
        if (!done.contains(f.value)) f,
    ];
    if (inPlay.isEmpty) return const Result.ok(LiveStanding.none);

    final snapshot = await _rulesets.currentSnapshotFor(
      FormatType.footballScoreline,
    );
    if (snapshot is Err<RulesetSnapshot>) {
      return Result.err(snapshot.error);
    }
    final rulesetResult = ScoringRuleset.fromSnapshot(
      (snapshot as Ok<RulesetSnapshot>).value,
    );
    if (rulesetResult is Err<ScoringRuleset>) {
      return Result.err(rulesetResult.error);
    }
    final ScoringRuleset ruleset = (rulesetResult as Ok<ScoringRuleset>).value;

    final Map<String, _Gain> gains = <String, _Gain>{};
    final Map<String, FixtureResult> asIfEnded = <String, FixtureResult>{};
    final List<LiveFixtureStanding> lines = <LiveFixtureStanding>[];
    for (final FixtureRef fixture in inPlay) {
      final LiveScore score = running[fixture.value]!;
      final resultNow = FixtureResult.create(
        fixture: fixture,
        homeGoals: score.homeGoals,
        awayGoals: score.awayGoals,
      );
      if (resultNow is Err<FixtureResult>) continue;
      final FixtureResult result = (resultNow as Ok<FixtureResult>).value;
      asIfEnded[fixture.value] = result;
      final predictions = await _fixturePredictions.listByFixture(fixture);
      if (predictions is Err<List<FixturePredictionView>>) {
        return Result.err(predictions.error);
      }
      int? mine;
      for (final FixturePredictionView view
          in (predictions as Ok<List<FixturePredictionView>>).value) {
        final FixturePrediction p = view.prediction;
        final FixtureScoreResult graded = _grade(
          ruleset,
          result,
          homeGoals: p.homeGoals,
          awayGoals: p.awayGoals,
          isDouble: p.isDouble,
        );
        gains.update(
          p.participantId.value,
          (g) => g.plus(graded),
          ifAbsent: () => _Gain.none.plus(graded),
        );
        if (p.participantId == me.id) mine = graded.points;
      }
      lines.add(
        LiveFixtureStanding(
          fixture: fixture,
          homeGoals: score.homeGoals,
          awayGoals: score.awayGoals,
          minute: score.minute,
          finished: score.finished,
          myPoints: mine,
        ),
      );
    }
    if (lines.isEmpty) return const Result.ok(LiveStanding.none);

    final totalsResult = await _totals.totalsFor(fixtures);
    if (totalsResult is Err<List<ParticipantFixtureTotals>>) {
      return Result.err(totalsResult.error);
    }
    final List<ParticipantFixtureTotals> now =
        (totalsResult as Ok<List<ParticipantFixtureTotals>>).value;
    final projected = _project(now, gains);
    if (projected is Err<List<ParticipantFixtureTotals>>) {
      return Result.err(projected.error);
    }
    final List<ParticipantFixtureTotals> then =
        (projected as Ok<List<ParticipantFixtureTotals>>).value;
    final rankNow = _rankOf(season, now, me.id);
    if (rankNow is Err<_Place?>) return Result.err(rankNow.error);
    final rankThen = _rankOf(season, then, me.id);
    if (rankThen is Err<_Place?>) return Result.err(rankThen.error);
    final _Place? placeNow = (rankNow as Ok<_Place?>).value;
    final _Place? placeThen = (rankThen as Ok<_Place?>).value;

    final duelsResult = await _duels.listDuelsFor(
      userId: principal.userId,
      since: _clock.nowUtc().subtract(duelWindow),
      limit: 50,
    );
    if (duelsResult is Err<List<DuelRecord>>) {
      return Result.err(duelsResult.error);
    }
    final List<LiveDuelStanding> duels = <LiveDuelStanding>[
      for (final DuelRecord d in (duelsResult as Ok<List<DuelRecord>>).value)
        if (asIfEnded[d.fixture.value] case final FixtureResult result)
          LiveDuelStanding(
            fixture: d.fixture,
            opponentName: d.opponentName,
            myPoints: _pickPoints(ruleset, result, d.myPick),
            opponentPoints: _pickPoints(ruleset, result, d.opponentPick),
          ),
    ];

    return Result.ok(
      LiveStanding(
        fixtures: List<LiveFixtureStanding>.unmodifiable(lines),
        duels: List<LiveDuelStanding>.unmodifiable(duels),
        rankNow: placeNow?.rank,
        rankIfEnded: placeThen?.rank,
        pointsNow: placeNow?.points ?? 0,
        pointsIfEnded: placeThen?.points ?? 0,
        players: then.length,
      ),
    );
  }

  static FixtureScoreResult _grade(
    ScoringRuleset ruleset,
    FixtureResult result, {
    required int homeGoals,
    required int awayGoals,
    required bool isDouble,
  }) => Scoring.gradeScoreline(
    prediction: FixtureScorePrediction.fromStored(
      fixture: result.fixture,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    ),
    result: result,
    ruleset: ruleset,
  );

  static int _pickPoints(
    ScoringRuleset ruleset,
    FixtureResult result,
    DuelPick? pick,
  ) => pick == null
      ? 0
      : _grade(
          ruleset,
          result,
          homeGoals: pick.homeGoals,
          awayGoals: pick.awayGoals,
          isDouble: pick.isDouble,
        ).points;

  /// [now] with every gain added, and a line for a player whose first
  /// points would come from a match in play.
  static Result<List<ParticipantFixtureTotals>> _project(
    List<ParticipantFixtureTotals> now,
    Map<String, _Gain> gains,
  ) {
    final List<ParticipantFixtureTotals> out = <ParticipantFixtureTotals>[];
    final Set<String> seen = <String>{};
    for (final ParticipantFixtureTotals line in now) {
      seen.add(line.participantId.value);
      final _Gain gain = gains[line.participantId.value] ?? _Gain.none;
      final int decided = line.decidedCount + gain.decided;
      final next = ParticipantFixtureTotals.of(
        participantId: line.participantId,
        totalPoints: line.totalPoints + gain.points,
        fixturesScored: decided > line.fixturesScored
            ? decided
            : line.fixturesScored,
        exactCount: line.exactCount + gain.exact,
        decidedCount: decided,
        referralPoints: line.referralPoints,
      );
      if (next is Err<ParticipantFixtureTotals>) return Result.err(next.error);
      out.add((next as Ok<ParticipantFixtureTotals>).value);
    }
    for (final MapEntry<String, _Gain> e in gains.entries) {
      if (seen.contains(e.key)) continue;
      final next = ParticipantFixtureTotals.of(
        participantId: ParticipantId(e.key),
        totalPoints: e.value.points,
        fixturesScored: e.value.decided,
        exactCount: e.value.exact,
        decidedCount: e.value.decided,
      );
      if (next is Err<ParticipantFixtureTotals>) return Result.err(next.error);
      out.add((next as Ok<ParticipantFixtureTotals>).value);
    }
    return Result.ok(out);
  }

  static Result<_Place?> _rankOf(
    SeasonId season,
    List<ParticipantFixtureTotals> totals,
    ParticipantId me,
  ) {
    final ranked = FixtureLeaderboard.rankTotals(
      seasonId: season,
      totals: totals,
      displayNames: const <String, String>{},
    );
    if (ranked is Err<FixtureLeaderboard>) return Result.err(ranked.error);
    for (final FixtureLeaderboardEntry e
        in (ranked as Ok<FixtureLeaderboard>).value.entries) {
      if (e.participantId == me) {
        return Result.ok(_Place(e.rank, e.totalPoints));
      }
    }
    return const Result.ok(null);
  }
}

final class _Place {
  const _Place(this.rank, this.points);

  final int rank;
  final int points;
}

/// What a player's predictions on the matches in play would add.
final class _Gain {
  const _Gain(this.points, this.exact, this.decided);

  static const _Gain none = _Gain(0, 0, 0);

  final int points;
  final int exact;
  final int decided;

  _Gain plus(FixtureScoreResult graded) => _Gain(
    points + graded.points,
    exact + (graded.grade == FixtureScoreGrade.exactScoreline ? 1 : 0),
    decided + 1,
  );
}
