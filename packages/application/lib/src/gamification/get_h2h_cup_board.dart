// NK309_04
/// Use-case: the Elite Cup of the month as every signed-in player or admin
/// reads it -- the three paths, their stages, pairs and fixtures, with the
/// two players' picks on each fixture (script 309).
///
/// **A pick is read only once it may be seen.** A player always reads his
/// own picks; the picks of anybody else, for a fixture that has not kicked
/// off or has no kickoff registered, never leave this use-case, and a side
/// that is withheld carries nothing of whether the player predicted. The
/// reader port withholds them too; this checks the rule again with
/// [GetMyH2hRound.hasKickedOff] against the server [Clock] before it builds
/// a side. An owner who must read them all reads another use-case, through
/// the owner route.
///
/// It reads; it decides, draws and writes nothing.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_my_h2h_cup.dart';
import 'package:application/src/gamification/get_my_h2h_round.dart';
import 'package:application/src/gamification/h2h_cup_month_pick.dart';
import 'package:application/src/gamification/ports/h2h_cup_pick_reader.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/h2h_round_fixture_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One player's side of one fixture, as the caller may read it.
final class H2hCupBoardSideView {
  /// Creates a side. A side that is not [revealed] cannot carry a [pick].
  const H2hCupBoardSideView({required this.revealed, this.pick})
    : assert(revealed || pick == null, 'a withheld side carries no pick');

  /// A side whose pick is withheld.
  const H2hCupBoardSideView.hidden() : revealed = false, pick = null;

  /// Whether the pick may be seen: the fixture has kicked off, or the side
  /// is the caller's own.
  final bool revealed;

  /// The player's pick, or null when withheld or when he did not predict.
  final H2hFixturePick? pick;
}

/// One fixture of a stage, with both players' sides of a pair.
final class H2hCupBoardFixtureView {
  /// Creates the fixture line.
  const H2hCupBoardFixtureView({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.kickoffAt,
    required this.state,
    required this.homeGoals,
    required this.awayGoals,
    required this.homeSide,
    required this.awaySide,
  });

  /// The fixture (UUID string).
  final String fixtureId;

  /// The home team's name.
  final String homeTeam;

  /// The away team's name.
  final String awayTeam;

  /// The home team's catalogue id, when known.
  final String? homeTeamId;

  /// The away team's catalogue id, when known.
  final String? awayTeamId;

  /// The kickoff (UTC), or null when none is registered: such a fixture
  /// counts as not started.
  final DateTime? kickoffAt;

  /// Where it stands.
  final H2hFixtureState state;

  /// The recorded home goals, or null before a result.
  final int? homeGoals;

  /// The recorded away goals, or null before a result.
  final int? awayGoals;

  /// The side of the pair's home player.
  final H2hCupBoardSideView homeSide;

  /// The side of the pair's away player.
  final H2hCupBoardSideView awaySide;
}

/// One pair of a stage, with the fixtures both players predicted.
final class H2hCupBoardPairView {
  /// Creates the pair.
  const H2hCupBoardPairView({
    required this.slot,
    required this.home,
    required this.away,
    required this.decided,
    required this.winner,
    required this.fixtures,
  });

  /// The pair's slot.
  final int slot;

  /// The first player.
  final MyH2hCupPlayer home;

  /// The second player.
  final MyH2hCupPlayer away;

  /// Whether the pair has a result.
  final bool decided;

  /// The winner, or null when undecided or when both lost.
  final UserId? winner;

  /// The stage's fixtures, by kickoff, with each player's side.
  final List<H2hCupBoardFixtureView> fixtures;
}

/// One stage of a path: its semi-finals or its final.
final class H2hCupBoardStageView {
  /// Creates the stage.
  const H2hCupBoardStageView({
    required this.round,
    required this.cupDay,
    required this.phase,
    required this.attempt,
    required this.pairs,
    this.day,
    this.bye,
  });

  /// Semi-final or final.
  final H2hCupRound round;

  /// The cup day, 1 to 4.
  final int cupDay;

  /// Where it stands.
  final MyH2hCupPhase phase;

  /// 1, or more for a stage carried to another day.
  final int attempt;

  /// The Riyadh day of its fixtures (a UTC midnight), or null before it is
  /// given one.
  final DateTime? day;

  /// Its pairs, by slot: empty before it is given a day.
  final List<H2hCupBoardPairView> pairs;

  /// The qualifier left without a pair (three qualifiers), or null.
  final MyH2hCupPlayer? bye;
}

/// One path of the cup (1, 2 or 3).
final class H2hCupBoardPathView {
  /// Creates the path.
  const H2hCupBoardPathView({
    required this.place,
    required this.stages,
    this.title,
  });

  /// The path: 1, 2 or 3.
  final int place;

  /// The path's stages: semi-finals, then the final.
  final List<H2hCupBoardStageView> stages;

  /// The path's title once decided.
  final MyH2hCupTitle? title;
}

/// The whole cup of the month for one reader.
final class H2hCupBoard {
  /// Creates the board.
  const H2hCupBoard({
    this.monthStart,
    this.paths = const <H2hCupBoardPathView>[],
  });

  /// No cup stands.
  static const H2hCupBoard none = H2hCupBoard();

  /// The month whose cup it is; null before a cup stands, when [paths] is
  /// empty too.
  final DateTime? monthStart;

  /// The cup's paths, 1 to 3; empty before the cup stands.
  final List<H2hCupBoardPathView> paths;
}

/// Reads the whole Elite Cup of the month for a signed-in player or admin.
///
/// The month is the one [H2hCupMonthPicker] chooses for the caller, the one
/// `GetMyH2hCup` reads. A caller outside the cup reads every path as a
/// watcher: his own picks are in no pair, so before kickoff every side is
/// withheld. A transient failure of a port is returned as it came.
///
/// Never throws; returns a typed [Result].
final class GetH2hCupBoard {
  /// Creates the use-case over its collaborators.
  const GetH2hCupBoard({
    required H2hCupStore cups,
    required H2hCupPickReader picks,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _cups = cups,
       _picks = picks,
       _profiles = profiles,
       _clock = clock;

  static const List<H2hCupRound> _rounds = <H2hCupRound>[
    H2hCupRound.semi,
    H2hCupRound.finale,
  ];

  final H2hCupStore _cups;
  final H2hCupPickReader _picks;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the cup board for [principal], any player or admin.
  Future<Result<H2hCupBoard>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final nowUtc = _clock.nowUtc().toUtc();
    final picked = await H2hCupMonthPicker.pick(
      cups: _cups,
      today: riyadhDayOf(nowUtc),
      user: principal.userId,
    );
    if (picked is Err<H2hCupMonthPick?>) {
      return Result.err(picked.error);
    }
    final pick = (picked as Ok<H2hCupMonthPick?>).value;
    if (pick == null) {
      return const Result.ok(H2hCupBoard.none);
    }
    final state = pick.state;

    final places = <int>[
      for (final place in H2hCupPolicy.places)
        if (state.entriesOf(place).isNotEmpty || state.titleOf(place) != null)
          place,
    ];
    final stages = <H2hCupStage>[];
    for (final place in places) {
      for (final round in _rounds) {
        final stage = state.stageOf(H2hCupStep(place, round));
        if (stage != null) {
          stages.add(stage);
        }
      }
    }

    var fixturesByStage = const <H2hCupStageId, List<H2hCupStageFixture>>{};
    if (stages.isNotEmpty) {
      final read = await _picks.fixturesOf(
        stages: stages,
        reader: principal.userId,
        nowUtc: nowUtc,
      );
      if (read is Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>) {
        return Result.err(read.error);
      }
      fixturesByStage =
          (read as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>).value;
    }

    final ids = <UserId>{};
    for (final place in places) {
      for (final entry in state.entriesOf(place)) {
        ids.add(entry.userId);
      }
      final title = state.titleOf(place);
      final champion = title?.champion;
      final runnerUp = title?.runnerUp;
      if (champion != null) {
        ids.add(champion);
      }
      if (runnerUp != null) {
        ids.add(runnerUp);
      }
    }
    for (final stage in stages) {
      for (final pair in stage.pairs) {
        ids
          ..add(pair.home)
          ..add(pair.away);
      }
    }
    final profiles = await _profiles.profilesOf(ids.toList());
    if (profiles is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profiles.error);
    }
    final names =
        (profiles as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
    final groups = <UserId, int>{
      for (final entry in state.entries) entry.userId: entry.groupNumber,
    };
    MyH2hCupPlayer player(UserId id) => MyH2hCupPlayer(
      userId: id,
      displayName: names[id]?.displayName ?? '',
      groupNumber: groups[id] ?? 0,
      isMe: id == principal.userId,
    );

    final paths = <H2hCupBoardPathView>[];
    for (final place in places) {
      final entries = state.entriesOf(place);
      final title = state.titleOf(place);
      final champion = title?.champion;
      final runnerUp = title?.runnerUp;
      final stageViews = <H2hCupBoardStageView>[];
      for (final round in _rounds) {
        final step = H2hCupStep(place, round);
        final stage = state.stageOf(step);
        final bye = stage != null && round == H2hCupRound.semi
            ? H2hCupPolicy.byeOf(entries, stage.pairs)
            : null;
        final fixtures = stage == null
            ? const <H2hCupStageFixture>[]
            : _byKickoff(
                fixturesByStage[stage.id] ?? const <H2hCupStageFixture>[],
              );
        stageViews.add(
          H2hCupBoardStageView(
            round: round,
            cupDay: step.cupDay,
            phase: GetMyH2hCup.phaseOf(step, stage, entries.length, title),
            attempt: stage?.attempt ?? 1,
            day: stage?.day,
            pairs: stage == null
                ? const <H2hCupBoardPairView>[]
                : <H2hCupBoardPairView>[
                    for (final pair in stage.pairs)
                      _pairView(
                        pair: pair,
                        result: GetMyH2hCup.resultOf(stage, pair.slot),
                        fixtures: fixtures,
                        caller: principal.userId,
                        nowUtc: nowUtc,
                        player: player,
                      ),
                  ],
            bye: bye == null ? null : player(bye),
          ),
        );
      }
      paths.add(
        H2hCupBoardPathView(
          place: place,
          stages: stageViews,
          title: title == null
              ? null
              : MyH2hCupTitle(
                  how: title.how,
                  champion: champion == null ? null : player(champion),
                  runnerUp: runnerUp == null ? null : player(runnerUp),
                ),
        ),
      );
    }

    return Result.ok(
      H2hCupBoard(
        monthStart: pick.month,
        paths: List<H2hCupBoardPathView>.unmodifiable(paths),
      ),
    );
  }

  static H2hCupBoardPairView _pairView({
    required H2hCupPair pair,
    required H2hCupResult? result,
    required List<H2hCupStageFixture> fixtures,
    required UserId caller,
    required DateTime nowUtc,
    required MyH2hCupPlayer Function(UserId) player,
  }) => H2hCupBoardPairView(
    slot: pair.slot,
    home: player(pair.home),
    away: player(pair.away),
    decided: result != null,
    winner: result?.winner,
    fixtures: <H2hCupBoardFixtureView>[
      for (final fixture in fixtures)
        _fixtureView(
          fixture: fixture,
          pair: pair,
          caller: caller,
          nowUtc: nowUtc,
        ),
    ],
  );

  static H2hCupBoardFixtureView _fixtureView({
    required H2hCupStageFixture fixture,
    required H2hCupPair pair,
    required UserId caller,
    required DateTime nowUtc,
  }) {
    final kickoff = fixture.kickoffAt?.toUtc();
    final started = GetMyH2hRound.hasKickedOff(
      kickoffAt: kickoff,
      nowUtc: nowUtc,
    );
    final H2hFixtureState state;
    if (!fixture.counted) {
      state = H2hFixtureState.voided;
    } else if (fixture.homeGoals != null && fixture.awayGoals != null) {
      state = H2hFixtureState.finished;
    } else if (started) {
      state = H2hFixtureState.live;
    } else {
      state = H2hFixtureState.notStarted;
    }
    return H2hCupBoardFixtureView(
      fixtureId: fixture.fixtureId,
      homeTeam: fixture.homeTeam,
      awayTeam: fixture.awayTeam,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      kickoffAt: kickoff,
      state: state,
      homeGoals: fixture.homeGoals,
      awayGoals: fixture.awayGoals,
      homeSide: _sideOf(
        owner: pair.home,
        caller: caller,
        started: started,
        fixture: fixture,
      ),
      awaySide: _sideOf(
        owner: pair.away,
        caller: caller,
        started: started,
        fixture: fixture,
      ),
    );
  }

  /// The side of [owner]: his pick when [caller] is [owner] or the fixture
  /// has [started], otherwise a withheld side that carries nothing.
  static H2hCupBoardSideView _sideOf({
    required UserId owner,
    required UserId caller,
    required bool started,
    required H2hCupStageFixture fixture,
  }) {
    if (owner != caller && !started) {
      return const H2hCupBoardSideView.hidden();
    }
    return H2hCupBoardSideView(revealed: true, pick: fixture.picks[owner]);
  }

  static List<H2hCupStageFixture> _byKickoff(List<H2hCupStageFixture> read) {
    final sorted = List<H2hCupStageFixture>.of(read)
      ..sort((a, b) {
        final ka = a.kickoffAt;
        final kb = b.kickoffAt;
        if (ka != null && kb != null) {
          final byTime = ka.compareTo(kb);
          if (byTime != 0) {
            return byTime;
          }
        } else if (ka != null) {
          return -1;
        } else if (kb != null) {
          return 1;
        }
        return a.fixtureId.compareTo(b.fixtureId);
      });
    return sorted;
  }
}
