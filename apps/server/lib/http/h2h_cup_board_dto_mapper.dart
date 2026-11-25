// NK312_01
/// Maps the Elite Cup board (script 309) to its wire shape (script 308).
///
/// **The only place a pick of the board becomes JSON.** A side that is not
/// revealed is written as `{"revealed": false}` and nothing else: no pick
/// key, no flag saying whether the player predicted. A revealed side with no
/// pick means the player did not predict. The owners' route
/// (`/owner/h2h-cup/picks`) maps the very same model with this mapper.
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

H2hCupBoardSideDto _side(H2hCupBoardSideView side) {
  if (!side.revealed) {
    return const H2hCupBoardSideDto.hidden();
  }
  final pick = side.pick;
  return H2hCupBoardSideDto(
    revealed: true,
    pick: pick == null
        ? null
        : H2hPickDto(
            homeGoals: pick.homeGoals,
            awayGoals: pick.awayGoals,
            isDouble: pick.isDouble,
            points: pick.points,
            exact: pick.exact,
          ),
  );
}

H2hCupBoardFixtureDto _fixture(H2hCupBoardFixtureView fixture) =>
    H2hCupBoardFixtureDto(
      fixtureId: fixture.fixtureId,
      homeTeam: fixture.homeTeam,
      awayTeam: fixture.awayTeam,
      homeTeamId: fixture.homeTeamId,
      awayTeamId: fixture.awayTeamId,
      kickoffAt: fixture.kickoffAt?.toUtc().toIso8601String(),
      state: fixture.state.wireName,
      homeGoals: fixture.homeGoals,
      awayGoals: fixture.awayGoals,
      homeSide: _side(fixture.homeSide),
      awaySide: _side(fixture.awaySide),
    );

H2hCupBoardPairDto _pair(H2hCupBoardPairView pair) => H2hCupBoardPairDto(
  slot: pair.slot,
  home: h2hCupPlayerToDto(pair.home),
  away: h2hCupPlayerToDto(pair.away),
  decided: pair.decided,
  winnerUserId: pair.winner?.value,
  homePoints: pair.homePoints,
  awayPoints: pair.awayPoints,
  fixtures: [for (final f in pair.fixtures) _fixture(f)],
);

H2hCupBoardStageDto _stage(H2hCupBoardStageView stage) {
  final day = stage.day;
  final bye = stage.bye;
  return H2hCupBoardStageDto(
    round: stage.round.wire,
    cupDay: stage.cupDay,
    phase: switch (stage.phase) {
      MyH2hCupPhase.waiting => 'waiting',
      MyH2hCupPhase.scheduled => 'scheduled',
      MyH2hCupPhase.live => 'live',
      MyH2hCupPhase.decided => 'decided',
      MyH2hCupPhase.skipped => 'skipped',
    },
    attempt: stage.attempt,
    day: day == null ? null : _day(day),
    pairs: [for (final p in stage.pairs) _pair(p)],
    bye: bye == null ? null : h2hCupPlayerToDto(bye),
  );
}

H2hCupBoardPathDto _path(H2hCupBoardPathView path) {
  final title = path.title;
  final champion = title?.champion;
  final runnerUp = title?.runnerUp;
  return H2hCupBoardPathDto(
    place: path.place,
    stages: [for (final s in path.stages) _stage(s)],
    title: title == null
        ? null
        : H2hCupTitleDto(
            how: title.how,
            champion: champion == null ? null : h2hCupPlayerToDto(champion),
            runnerUp: runnerUp == null ? null : h2hCupPlayerToDto(runnerUp),
          ),
  );
}

/// The cup board on the wire.
H2hCupBoardDto h2hCupBoardToDto(H2hCupBoard board) {
  final month = board.monthStart;
  return H2hCupBoardDto(
    monthStart: month == null ? null : _day(month),
    paths: [for (final p in board.paths) _path(p)],
  );
}
