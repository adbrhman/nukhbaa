/// Use-case: the caller's Elite Cup of the head-to-head league (NK185,
/// migration 0190), read by the player himself.
///
/// A player who finished first, second or third in an elite group of a
/// month plays the cup of his place against the other qualifiers of that
/// place. This reads what the server stored -- the qualifiers, the stages
/// of his path with their days, pairs and results, and the title -- and
/// names it. Nothing is drawn, decided or written here.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/h2h_cup_month_pick.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where the caller stands with the cup.
enum MyH2hCupState {
  /// The caller is in no cup that is open now.
  notQualified,

  /// The caller qualified for the cup of a month.
  qualified,

  /// The caller is outside the cup but may watch the first places' path
  /// (the group leaders): read-only, nothing of his own in it.
  spectator,
}

/// Where one stage of the caller's path stands.
enum MyH2hCupPhase {
  /// Not given a day yet: it waits for the stage before it.
  waiting,

  /// Given a day and its pairs; the fixtures are not frozen yet.
  scheduled,

  /// Frozen; not every result of the day is in.
  live,

  /// Every pair is decided.
  decided,

  /// Never played: two qualifiers go straight to the final, and a path with
  /// one qualifier (or none) has no final.
  skipped,
}

/// A player of the caller's path.
final class MyH2hCupPlayer {
  /// Creates a player.
  const MyH2hCupPlayer({
    required this.userId,
    required this.displayName,
    required this.groupNumber,
    required this.isMe,
  });

  /// The player.
  final UserId userId;

  /// The platform display name, empty when the player has no profile.
  final String displayName;

  /// The elite group the player qualified from: 1 to 4, or 0 when unknown.
  final int groupNumber;

  /// Whether this is the caller.
  final bool isMe;
}

/// One pair of a stage.
final class MyH2hCupPair {
  /// Creates a pair.
  const MyH2hCupPair({
    required this.slot,
    required this.home,
    required this.away,
    required this.isMine,
    this.result,
  });

  /// The pair's slot.
  final int slot;

  /// The first side.
  final MyH2hCupPlayer home;

  /// The second side.
  final MyH2hCupPlayer away;

  /// Whether the caller is one of the two.
  final bool isMine;

  /// The decision, or null until the stage is decided.
  final H2hCupResult? result;

  /// Whether the pair has a result.
  bool get decided => result != null;
}

/// One stage of the caller's path: its semi-finals or its final.
final class MyH2hCupStage {
  /// Creates a stage.
  const MyH2hCupStage({
    required this.round,
    required this.cupDay,
    required this.expectedDay,
    required this.phase,
    required this.attempt,
    required this.pairs,
    this.day,
    this.fixtureCount,
    this.bye,
  });

  /// Semi-final or final.
  final H2hCupRound round;

  /// The cup day, 1 to 4 (`H2hCupStep.cupDay`).
  final int cupDay;

  /// The league day it is expected on when nothing is late: 20 to 23.
  final int expectedDay;

  /// Where it stands.
  final MyH2hCupPhase phase;

  /// 1, or more for a stage carried to another day.
  final int attempt;

  /// The Riyadh day of its fixtures (a UTC midnight), or null before it is
  /// given one.
  final DateTime? day;

  /// The fixtures the day held when it was given, or null before.
  final int? fixtureCount;

  /// Its pairs, by slot: empty before it is given a day.
  final List<MyH2hCupPair> pairs;

  /// The qualifier left without a pair (three qualifiers), or null.
  final MyH2hCupPlayer? bye;
}

/// The title of the caller's path.
final class MyH2hCupTitle {
  /// Creates a title.
  const MyH2hCupTitle({required this.how, this.champion, this.runnerUp});

  /// `final`, `walkover` or `vacant`.
  final String how;

  /// The champion, or null when vacant.
  final MyH2hCupPlayer? champion;

  /// The runner-up, or null.
  final MyH2hCupPlayer? runnerUp;
}

/// The caller's cup.
final class MyH2hCup {
  /// Creates the view.
  const MyH2hCup({
    required this.state,
    this.monthStart,
    this.place = 0,
    this.groupNumber = 0,
    this.entrants = const <MyH2hCupPlayer>[],
    this.stages = const <MyH2hCupStage>[],
    this.title,
  });

  /// The caller is in no open cup.
  static const MyH2hCup notQualified = MyH2hCup(
    state: MyH2hCupState.notQualified,
  );

  /// Where the caller stands.
  final MyH2hCupState state;

  /// The month whose cup it is.
  final DateTime? monthStart;

  /// The caller's path: 1, 2 or 3 (0 when not qualified).
  final int place;

  /// The caller's elite group (0 when not qualified).
  final int groupNumber;

  /// The qualifiers of the caller's path, by group.
  final List<MyH2hCupPlayer> entrants;

  /// The two stages of the path: semi-finals, then the final.
  final List<MyH2hCupStage> stages;

  /// The path's title once decided.
  final MyH2hCupTitle? title;
}

/// Reads the caller's Elite Cup.
///
/// The cup of the current Riyadh month is read first, then the month before
/// it: the cup of a month opens after its 19 rounds, and may still be on in
/// the next month. A cup whose three titles were decided more than
/// [lingerDays] days ago is not shown any more.
///
/// Never throws; returns a typed [Result].
final class GetMyH2hCup {
  /// Creates the use-case over its collaborators.
  const GetMyH2hCup({
    required H2hCupStore cups,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _cups = cups,
       _profiles = profiles,
       _clock = clock;

  /// Days a finished cup stays on the caller's screen.
  static const int lingerDays = H2hCupMonthPicker.lingerDays;

  /// The path a player outside the cup may watch: the first places, the
  /// group leaders.
  static const int spectatorPlace = H2hCupMonthPicker.spectatorPlace;

  final H2hCupStore _cups;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the cup of [principal], any player.
  Future<Result<MyH2hCup>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final today = riyadhDayOf(_clock.nowUtc());
    final picked = await H2hCupMonthPicker.pick(
      cups: _cups,
      today: today,
      user: principal.userId,
    );
    if (picked is Err<H2hCupMonthPick?>) {
      return Result.err(picked.error);
    }
    final pick = (picked as Ok<H2hCupMonthPick?>).value;
    if (pick == null) {
      return const Result.ok(MyH2hCup.notQualified);
    }
    return _view(
      pick.month,
      pick.state,
      principal.userId,
      place: pick.place,
      groupNumber: pick.groupNumber,
      watching: pick.watching,
    );
  }

  Future<Result<MyH2hCup>> _view(
    DateTime month,
    H2hCupState state,
    UserId me, {
    required int place,
    int groupNumber = 0,
    bool watching = false,
  }) async {
    final entries = state.entriesOf(place);
    final steps = <H2hCupStep>[
      H2hCupStep(place, H2hCupRound.semi),
      H2hCupStep(place, H2hCupRound.finale),
    ];
    final title = state.titleOf(place);

    final ids = <UserId>{for (final e in entries) e.userId};
    for (final step in steps) {
      final stage = state.stageOf(step);
      if (stage == null) {
        continue;
      }
      for (final pair in stage.pairs) {
        ids
          ..add(pair.home)
          ..add(pair.away);
      }
    }
    final champion = title?.champion;
    final runnerUp = title?.runnerUp;
    if (champion != null) {
      ids.add(champion);
    }
    if (runnerUp != null) {
      ids.add(runnerUp);
    }

    final profiles = await _profiles.profilesOf(ids.toList());
    if (profiles is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profiles.error);
    }
    final names =
        (profiles as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
    final groups = <UserId, int>{
      for (final e in entries) e.userId: e.groupNumber,
    };
    MyH2hCupPlayer player(UserId id) => MyH2hCupPlayer(
      userId: id,
      displayName: names[id]?.displayName ?? '',
      groupNumber: groups[id] ?? 0,
      isMe: id == me,
    );

    final stages = <MyH2hCupStage>[];
    for (final step in steps) {
      final stage = state.stageOf(step);
      final bye = stage != null && step.round == H2hCupRound.semi
          ? H2hCupPolicy.byeOf(entries, stage.pairs)
          : null;
      stages.add(
        MyH2hCupStage(
          round: step.round,
          cupDay: step.cupDay,
          expectedDay: step.expectedDay,
          phase: _phaseOf(step, stage, entries.length, title),
          attempt: stage?.attempt ?? 1,
          day: stage?.day,
          fixtureCount: stage?.fixtureCount,
          pairs: stage == null
              ? const <MyH2hCupPair>[]
              : <MyH2hCupPair>[
                  for (final pair in stage.pairs)
                    MyH2hCupPair(
                      slot: pair.slot,
                      home: player(pair.home),
                      away: player(pair.away),
                      isMine: pair.home == me || pair.away == me,
                      result: _resultOf(stage, pair.slot),
                    ),
                ],
          bye: bye == null ? null : player(bye),
        ),
      );
    }

    return Result.ok(
      MyH2hCup(
        state: watching ? MyH2hCupState.spectator : MyH2hCupState.qualified,
        monthStart: month,
        place: place,
        groupNumber: groupNumber,
        entrants: <MyH2hCupPlayer>[for (final e in entries) player(e.userId)],
        stages: stages,
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

  static MyH2hCupPhase _phaseOf(
    H2hCupStep step,
    H2hCupStage? stage,
    int entrants,
    H2hCupTitle? title,
  ) {
    if (stage == null) {
      final neverPlayed = step.round == H2hCupRound.semi
          ? entrants <= 2
          : title != null;
      return neverPlayed ? MyH2hCupPhase.skipped : MyH2hCupPhase.waiting;
    }
    if (stage.decided) {
      return MyH2hCupPhase.decided;
    }
    return stage.locked ? MyH2hCupPhase.live : MyH2hCupPhase.scheduled;
  }

  static H2hCupResult? _resultOf(H2hCupStage stage, int slot) {
    for (final result in stage.results) {
      if (result.slot == slot) {
        return result;
      }
    }
    return null;
  }
}
