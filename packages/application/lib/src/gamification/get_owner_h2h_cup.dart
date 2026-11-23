/// Use-case: the whole Elite Cup of a month, for the owners' page (script
/// 304).
///
/// Every path (the first, second and third places), its qualifiers, both
/// stages with their day, pairs and results, its title, and the month's
/// rounds. The route is behind the owners' gate; the role check here is the
/// second lock. Nothing is drawn, decided or written here.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_my_h2h_cup.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One path of the cup.
final class OwnerH2hCupPath {
  /// Creates a path.
  const OwnerH2hCupPath({
    required this.place,
    required this.entrants,
    required this.stages,
    this.title,
  });

  /// The place in the elite groups the path is for: 1, 2 or 3.
  final int place;

  /// Its qualifiers, by group.
  final List<MyH2hCupPlayer> entrants;

  /// Semi-finals, then the final.
  final List<MyH2hCupStage> stages;

  /// The title once decided.
  final MyH2hCupTitle? title;
}

/// One round of the month.
final class OwnerH2hCupRound {
  /// Creates a round.
  const OwnerH2hCupRound({
    required this.number,
    required this.day,
    required this.fixtureCount,
    required this.locked,
    required this.bySystem,
  });

  /// Its number in the month.
  final int number;

  /// Its Riyadh day (a UTC midnight).
  final DateTime day;

  /// The fixtures it held when approved.
  final int fixtureCount;

  /// Whether its fixture list is frozen.
  final bool locked;

  /// Whether the scheduler approved it, not an admin.
  final bool bySystem;
}

/// A month of the cup window and whether it holds a cup.
final class OwnerH2hCupMonth {
  /// Creates the line.
  const OwnerH2hCupMonth({required this.monthStart, required this.hasCup});

  /// The first day of the month.
  final DateTime monthStart;

  /// Whether the month has qualifiers.
  final bool hasCup;
}

/// The cup of one month.
final class OwnerH2hCup {
  /// Creates the view.
  const OwnerH2hCup({
    required this.monthStart,
    required this.months,
    required this.rounds,
    required this.paths,
  });

  /// The month shown.
  final DateTime monthStart;

  /// The months the cup keeps (the current one and the two before it).
  final List<OwnerH2hCupMonth> months;

  /// The month's approved rounds.
  final List<OwnerH2hCupRound> rounds;

  /// The three paths; empty before the month has qualifiers.
  final List<OwnerH2hCupPath> paths;
}

/// Reads the whole cup of a month.
///
/// Never throws; returns a typed [Result].
final class GetOwnerH2hCup {
  /// Creates the use-case over its collaborators.
  const GetOwnerH2hCup({
    required H2hCupStore cups,
    required H2hRoundStore rounds,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _cups = cups,
       _rounds = rounds,
       _profiles = profiles,
       _clock = clock;

  final H2hCupStore _cups;
  final H2hRoundStore _rounds;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the cup of [month] (a month's first day), or of the latest month
  /// holding one when null.
  Future<Result<OwnerH2hCup>> call({
    required AuthenticatedUser principal,
    DateTime? month,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final today = riyadhDayOf(_clock.nowUtc());
    final current = H2hLeaguePolicy.monthStartOf(today);
    final window = <DateTime>[
      for (final back in const [2, 1, 0])
        DateTime.utc(current.year, current.month - back),
    ];
    final elite = [
      for (final m in window)
        if (H2hLeaguePolicy.usesEliteDraw(m)) m,
    ];

    final states = <DateTime, H2hCupState>{};
    for (final m in elite) {
      final read = await _cups.stateOf(m);
      if (read is Err<H2hCupState>) {
        return Result.err(read.error);
      }
      states[m] = (read as Ok<H2hCupState>).value;
    }
    final months = <OwnerH2hCupMonth>[
      for (final m in elite)
        OwnerH2hCupMonth(monthStart: m, hasCup: states[m]!.entries.isNotEmpty),
    ];

    final DateTime shown;
    if (month != null) {
      shown = DateTime.utc(month.year, month.month);
    } else {
      shown = months
          .lastWhere(
            (m) => m.hasCup,
            orElse: () => OwnerH2hCupMonth(monthStart: current, hasCup: false),
          )
          .monthStart;
    }

    var state = states[shown];
    if (state == null) {
      final read = await _cups.stateOf(shown);
      if (read is Err<H2hCupState>) {
        return Result.err(read.error);
      }
      state = (read as Ok<H2hCupState>).value;
    }

    final roundsRead = await _rounds.roundsOf(shown);
    if (roundsRead is Err<List<H2hRound>>) {
      return Result.err(roundsRead.error);
    }
    final rounds = (roundsRead as Ok<List<H2hRound>>).value;

    final ids = <UserId>{for (final e in state.entries) e.userId};
    for (final stage in state.stages) {
      for (final pair in stage.pairs) {
        ids
          ..add(pair.home)
          ..add(pair.away);
      }
    }
    for (final title in state.titles) {
      final champion = title.champion;
      final runnerUp = title.runnerUp;
      if (champion != null) {
        ids.add(champion);
      }
      if (runnerUp != null) {
        ids.add(runnerUp);
      }
    }
    final profiles = await _profiles.profilesOf(ids.toList());
    if (profiles is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profiles.error);
    }
    final names =
        (profiles as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;
    final groups = <UserId, int>{
      for (final e in state.entries) e.userId: e.groupNumber,
    };
    MyH2hCupPlayer player(UserId id) => MyH2hCupPlayer(
      userId: id,
      displayName: names[id]?.displayName ?? '',
      groupNumber: groups[id] ?? 0,
      isMe: false,
    );

    final paths = <OwnerH2hCupPath>[];
    if (state.entries.isNotEmpty) {
      for (final place in H2hCupPolicy.places) {
        paths.add(_path(place, state, player));
      }
    }

    return Result.ok(
      OwnerH2hCup(
        monthStart: shown,
        months: months,
        rounds: [
          for (final r in rounds)
            OwnerH2hCupRound(
              number: r.number,
              day: r.day,
              fixtureCount: r.fixtureCount,
              locked: r.lockedAt != null,
              bySystem: r.approvedBy == null,
            ),
        ],
        paths: paths,
      ),
    );
  }

  static OwnerH2hCupPath _path(
    int place,
    H2hCupState state,
    MyH2hCupPlayer Function(UserId) player,
  ) {
    final entries = state.entriesOf(place);
    final title = state.titleOf(place);
    final stages = <MyH2hCupStage>[];
    for (final round in const [H2hCupRound.semi, H2hCupRound.finale]) {
      final step = H2hCupStep(place, round);
      final stage = state.stageOf(step);
      final bye = stage != null && round == H2hCupRound.semi
          ? H2hCupPolicy.byeOf(entries, stage.pairs)
          : null;
      stages.add(
        MyH2hCupStage(
          round: round,
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
                      isMine: false,
                      result: _resultOf(stage, pair.slot),
                    ),
                ],
          bye: bye == null ? null : player(bye),
        ),
      );
    }
    final champion = title?.champion;
    final runnerUp = title?.runnerUp;
    return OwnerH2hCupPath(
      place: place,
      entrants: [for (final e in entries) player(e.userId)],
      stages: stages,
      title: title == null
          ? null
          : MyH2hCupTitle(
              how: title.how,
              champion: champion == null ? null : player(champion),
              runnerUp: runnerUp == null ? null : player(runnerUp),
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
