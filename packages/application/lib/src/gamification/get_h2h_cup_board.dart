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
    required this.homePoints,
    required this.awayPoints,
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

  // NK330_01
  /// The first player's prediction points on the stage's fixtures: the
  /// figure the cup decided the pair with once it is [decided]; until then
  /// the stored points of the counted fixtures this board shows for his
  /// side (0 before any score).
  final int homePoints;

  /// The second player's prediction points, as [homePoints].
  final int awayPoints;

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

  /// The cup's paths, 1 to 3; empty before the cup stands. NK360_01e: the
  /// bracket of December 2026 on is one path, the place 1, with all sixteen
  /// players and its four rounds.
  final List<H2hCupBoardPathView> paths;
}

// NK310_02
/// Builds the board of one month's cup for one reader (script 310).
///
/// Shared by the player's use-case ([GetH2hCupBoard]) and the owners'
/// (`GetOwnerH2hCupPicks`). It is **not exported** from the package, so
/// nothing outside the application layer can ask for an unmasked board.
///
/// With `unmasked` false, every side other than the caller's is withheld
/// until its fixture has kicked off, checked here against the server clock
/// whatever the reader handed over. With it true, which only the owners'
/// use-case passes, every side shows the pick it has.
final class H2hCupBoardBuilder {
  const H2hCupBoardBuilder._();

  static const List<H2hCupRound> _rounds = <H2hCupRound>[
    H2hCupRound.semi,
    H2hCupRound.finale,
  ];

  // NK360_01a
  /// The rounds of the one bracket of sixteen (December 2026 on), in the
  /// order they are played.
  static const List<H2hCupRound> _bracketRounds = <H2hCupRound>[
    H2hCupRound.round16,
    H2hCupRound.quarter,
    H2hCupRound.semi,
    H2hCupRound.finale,
  ];

  /// Builds the board of [state], the cup of [monthStart], as [caller] reads
  /// it. [readFixtures] reads the fixtures of the stages, once, and is the
  /// only place a pick comes from.
  static Future<Result<H2hCupBoard>> build({
    required H2hCupState state,
    required DateTime monthStart,
    required UserId caller,
    required DateTime nowUtc,
    required bool unmasked,
    required WeeklyLeagueProfileReader profiles,
    required Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>>
    Function(List<H2hCupStage> stages)
    readFixtures,
  }) async {
    // NK360_01b: from December 2026 the cup is one bracket of sixteen, so
    // the board has one path, the place 1, holding every qualifier and the
    // four rounds of the bracket; before it, three paths of a semi-final and
    // a final. The month decides, never today's date.
    final bracket = H2hCupPolicy.isBracket(monthStart);
    final rounds = bracket ? _bracketRounds : _rounds;
    List<H2hCupEntry> entriesOf(int place) =>
        bracket ? state.entries : state.entriesOf(place);
    H2hCupStep stepOf(int place, H2hCupRound round) =>
        H2hCupStep(place, round, bracket: bracket);
    final places = <int>[
      for (final place in bracket ? const <int>[1] : H2hCupPolicy.places)
        if (entriesOf(place).isNotEmpty || state.titleOf(place) != null) place,
    ];
    final stages = <H2hCupStage>[];
    for (final place in places) {
      for (final round in rounds) {
        final stage = state.stageOf(stepOf(place, round));
        if (stage != null) {
          stages.add(stage);
        }
      }
    }

    var fixturesByStage = const <H2hCupStageId, List<H2hCupStageFixture>>{};
    if (stages.isNotEmpty) {
      final read = await readFixtures(stages);
      if (read is Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>) {
        return Result.err(read.error);
      }
      fixturesByStage =
          (read as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>).value;
    }

    final ids = <UserId>{};
    for (final place in places) {
      for (final entry in entriesOf(place)) {
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
    final named = await profiles.profilesOf(ids.toList());
    if (named is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(named.error);
    }
    final names = (named as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
    final groups = <UserId, int>{
      for (final entry in state.entries) entry.userId: entry.groupNumber,
    };
    MyH2hCupPlayer player(UserId id) => MyH2hCupPlayer(
      userId: id,
      displayName: names[id]?.displayName ?? '',
      groupNumber: groups[id] ?? 0,
      isMe: id == caller,
    );

    final paths = <H2hCupBoardPathView>[];
    for (final place in places) {
      final entries = entriesOf(place);
      final title = state.titleOf(place);
      final champion = title?.champion;
      final runnerUp = title?.runnerUp;
      final stageViews = <H2hCupBoardStageView>[];
      // NK360_01c: who is still in the bracket before each round, as
      // RunH2hCup counts them (the winners of the round before and the one it
      // left without a pair); null once a round is not decided yet.
      var alive = bracket ? <UserId>[for (final e in entries) e.userId] : null;
      for (final round in rounds) {
        final step = stepOf(place, round);
        final stage = state.stageOf(step);
        final bye = _byeOf(
          bracket: bracket,
          round: round,
          stage: stage,
          entries: entries,
          alive: alive,
        );
        alive = bracket ? _through(stage, alive, bye) : null;
        final fixtures = stage == null
            ? const <H2hCupStageFixture>[]
            : _byKickoff(
                fixturesByStage[stage.id] ?? const <H2hCupStageFixture>[],
              );
        stageViews.add(
          H2hCupBoardStageView(
            round: round,
            cupDay: step.cupDay,
            phase: bracket && stage == null
                ? (title == null
                      ? MyH2hCupPhase.waiting
                      : MyH2hCupPhase.skipped)
                : GetMyH2hCup.phaseOf(step, stage, entries.length, title),
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
                        caller: caller,
                        nowUtc: nowUtc,
                        unmasked: unmasked,
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
        monthStart: monthStart,
        paths: List<H2hCupBoardPathView>.unmodifiable(paths),
      ),
    );
  }

  // NK360_01d
  /// The player [stage] left without a pair. A three-path cup: the one of
  /// [entries] its semi-finals left out (three qualifiers). The bracket: the
  /// one of [alive] its pairs left out, or null when [alive] is not known
  /// (a round before it is still to be decided).
  static UserId? _byeOf({
    required bool bracket,
    required H2hCupRound round,
    required H2hCupStage? stage,
    required List<H2hCupEntry> entries,
    required List<UserId>? alive,
  }) {
    if (stage == null) {
      return null;
    }
    if (!bracket) {
      return round == H2hCupRound.semi
          ? H2hCupPolicy.byeOf(entries, stage.pairs)
          : null;
    }
    if (alive == null) {
      return null;
    }
    final paired = <UserId>{
      for (final pair in stage.pairs) ...[pair.home, pair.away],
    };
    for (final id in alive) {
      if (!paired.contains(id)) {
        return id;
      }
    }
    return null;
  }

  /// The players that go on after [stage] in the bracket: its winners by
  /// slot, then [bye]; null while [stage] is not decided or [alive] is not
  /// known, so a round after it shows no bye of its own.
  static List<UserId>? _through(
    H2hCupStage? stage,
    List<UserId>? alive,
    UserId? bye,
  ) {
    if (stage == null || alive == null || !stage.decided) {
      return null;
    }
    final results = [...stage.results]
      ..sort((a, b) => a.slot.compareTo(b.slot));
    return <UserId>[
      for (final r in results)
        if (r.winner != null) r.winner!,
      if (bye != null) bye,
    ];
  }

  static H2hCupBoardPairView _pairView({
    required H2hCupPair pair,
    required H2hCupResult? result,
    required List<H2hCupStageFixture> fixtures,
    required UserId caller,
    required DateTime nowUtc,
    required bool unmasked,
    required MyH2hCupPlayer Function(UserId) player,
  }) {
    final views = <H2hCupBoardFixtureView>[
      for (final fixture in fixtures)
        _fixtureView(
          fixture: fixture,
          pair: pair,
          caller: caller,
          nowUtc: nowUtc,
          unmasked: unmasked,
        ),
    ];
    // NK330_02
    return H2hCupBoardPairView(
      slot: pair.slot,
      home: player(pair.home),
      away: player(pair.away),
      decided: result != null,
      winner: result?.winner,
      homePoints: result?.home.points ?? _pointsOf(views, home: true),
      awayPoints: result?.away.points ?? _pointsOf(views, home: false),
      fixtures: views,
    );
  }

  // NK330_03
  /// The points of one side of a pair the cup has not decided: the stored
  /// points of its picks on the fixtures that still count, as the stage sums
  /// them (a score still pending is 0). It adds only what [fixtures] already
  /// show, so a side that is withheld contributes nothing, and no figure
  /// reaches a reader that its pick would not.
  static int _pointsOf(
    List<H2hCupBoardFixtureView> fixtures, {
    required bool home,
  }) {
    var total = 0;
    for (final fixture in fixtures) {
      if (fixture.state == H2hFixtureState.voided) {
        continue;
      }
      final side = home ? fixture.homeSide : fixture.awaySide;
      total += side.pick?.points ?? 0;
    }
    return total;
  }

  static H2hCupBoardFixtureView _fixtureView({
    required H2hCupStageFixture fixture,
    required H2hCupPair pair,
    required UserId caller,
    required DateTime nowUtc,
    required bool unmasked,
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
        unmasked: unmasked,
        fixture: fixture,
      ),
      awaySide: _sideOf(
        owner: pair.away,
        caller: caller,
        started: started,
        unmasked: unmasked,
        fixture: fixture,
      ),
    );
  }

  /// The side of [owner]: his pick when the board is [unmasked], when
  /// [caller] is [owner], or when the fixture has [started]; otherwise a
  /// withheld side that carries nothing.
  static H2hCupBoardSideView _sideOf({
    required UserId owner,
    required UserId caller,
    required bool started,
    required bool unmasked,
    required H2hCupStageFixture fixture,
  }) {
    if (!unmasked && owner != caller && !started) {
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
    return H2hCupBoardBuilder.build(
      state: pick.state,
      monthStart: pick.month,
      caller: principal.userId,
      nowUtc: nowUtc,
      unmasked: false,
      profiles: _profiles,
      readFixtures: (stages) => _picks.fixturesOf(
        stages: stages,
        reader: principal.userId,
        nowUtc: nowUtc,
      ),
    );
  }
}
