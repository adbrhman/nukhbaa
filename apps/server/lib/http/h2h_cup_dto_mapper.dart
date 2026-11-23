/// Maps the caller's Elite Cup (NK185, migration 0190) to its wire shape.
///
/// Names, days and the figures that decided a pair only; no prediction of
/// anybody is read here, so none can cross the wire.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

String _day(DateTime day) {
  final d = day.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

H2hCupPlayerDto _player(MyH2hCupPlayer p) => H2hCupPlayerDto(
  userId: p.userId.value,
  displayName: p.displayName,
  groupNumber: p.groupNumber,
  isMe: p.isMe,
);

H2hCupPairDto _pair(MyH2hCupPair pair) {
  final result = pair.result;
  return H2hCupPairDto(
    slot: pair.slot,
    home: _player(pair.home),
    away: _player(pair.away),
    isMine: pair.isMine,
    decided: pair.decided,
    outcome: result?.outcome,
    winnerUserId: result?.winner?.value,
    homePoints: result?.home.points,
    awayPoints: result?.away.points,
    homeExact: result?.home.exact,
    awayExact: result?.away.exact,
  );
}

H2hCupStageDto _stage(MyH2hCupStage stage) {
  final day = stage.day;
  final bye = stage.bye;
  return H2hCupStageDto(
    round: stage.round.wire,
    cupDay: stage.cupDay,
    expectedDay: stage.expectedDay,
    phase: switch (stage.phase) {
      MyH2hCupPhase.waiting => 'waiting',
      MyH2hCupPhase.scheduled => 'scheduled',
      MyH2hCupPhase.live => 'live',
      MyH2hCupPhase.decided => 'decided',
      MyH2hCupPhase.skipped => 'skipped',
    },
    attempt: stage.attempt,
    day: day == null ? null : _day(day),
    fixtureCount: stage.fixtureCount,
    pairs: [for (final pair in stage.pairs) _pair(pair)],
    bye: bye == null ? null : _player(bye),
  );
}

/// A player of a path on the wire (the owners' cup reads it too).
H2hCupPlayerDto h2hCupPlayerToDto(MyH2hCupPlayer player) => _player(player);

/// A stage on the wire (the owners' cup reads it too).
H2hCupStageDto h2hCupStageToDto(MyH2hCupStage stage) => _stage(stage);

/// The caller's cup on the wire.
MyH2hCupDto myH2hCupToDto(MyH2hCup cup) {
  final month = cup.monthStart;
  final title = cup.title;
  final champion = title?.champion;
  final runnerUp = title?.runnerUp;
  return MyH2hCupDto(
    state: switch (cup.state) {
      MyH2hCupState.qualified => 'qualified',
      MyH2hCupState.notQualified => 'not_qualified',
    },
    monthStart: month == null ? null : _day(month),
    place: cup.place,
    groupNumber: cup.groupNumber,
    entrants: [for (final p in cup.entrants) _player(p)],
    stages: [for (final s in cup.stages) _stage(s)],
    title: title == null
        ? null
        : H2hCupTitleDto(
            how: title.how,
            champion: champion == null ? null : _player(champion),
            runnerUp: runnerUp == null ? null : _player(runnerUp),
          ),
  );
}
