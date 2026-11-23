/// Maps the owners' whole Elite Cup (script 304) to its wire shape. Names,
/// days and the figures that decided a pair only.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:server/http/h2h_cup_dto_mapper.dart';

String _day(DateTime day) {
  final d = day.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

OwnerH2hCupPathDto _path(OwnerH2hCupPath path) {
  final title = path.title;
  final champion = title?.champion;
  final runnerUp = title?.runnerUp;
  return OwnerH2hCupPathDto(
    place: path.place,
    entrants: [for (final p in path.entrants) h2hCupPlayerToDto(p)],
    stages: [for (final s in path.stages) h2hCupStageToDto(s)],
    title: title == null
        ? null
        : H2hCupTitleDto(
            how: title.how,
            champion: champion == null ? null : h2hCupPlayerToDto(champion),
            runnerUp: runnerUp == null ? null : h2hCupPlayerToDto(runnerUp),
          ),
  );
}

/// The owners' cup on the wire.
OwnerH2hCupDto ownerH2hCupToDto(OwnerH2hCup cup) => OwnerH2hCupDto(
  monthStart: _day(cup.monthStart),
  months: [
    for (final m in cup.months)
      OwnerH2hCupMonthDto(monthStart: _day(m.monthStart), hasCup: m.hasCup),
  ],
  rounds: [
    for (final r in cup.rounds)
      OwnerH2hCupRoundDto(
        number: r.number,
        day: _day(r.day),
        fixtureCount: r.fixtureCount,
        locked: r.locked,
        bySystem: r.bySystem,
      ),
  ],
  paths: [for (final p in cup.paths) _path(p)],
);
