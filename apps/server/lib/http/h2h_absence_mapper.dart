import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// The admin's view of relegation for absence on the wire
/// (`GET /admin/h2h/absence`, NK183).
H2hAbsenceViewDto h2hAbsenceViewToDto(H2hAbsenceView view) {
  H2hAbsencePlayerDto player(UserId id) => H2hAbsencePlayerDto(
    userId: id.value,
    displayName: view.profiles[id]?.displayName,
  );
  H2hAbsenceFactsDto facts(H2hCandidateFacts f) => H2hAbsenceFactsDto(
    missed: f.missed,
    points: f.points,
    exact: f.exact,
    activeDays: f.activeDays,
  );
  return H2hAbsenceViewDto(
    monthStart: _isoDay(view.monthStart),
    active: view.active,
    nextRound: view.nextRound?.number,
    relegatesAt: view.relegatesAt?.toUtc().toIso8601String(),
    rounds: [
      for (final r in view.rounds)
        H2hAbsenceRoundDto(
          roundId: r.round.id.value,
          round: r.round.number,
          day: _isoDay(r.round.day),
          locked: r.round.locked,
          counted: r.counted,
          absent: r.absent,
          excusedReason: r.excusal?.reason,
        ),
    ],
    watch: [
      for (final w in view.watch)
        H2hAbsenceWatchDto(
          player: player(w.seat.userId),
          group: w.groupNumber,
          absentRounds: [for (final r in w.absentRounds) r.number],
          warned: w.warned,
        ),
    ],
    candidates: [
      for (final c in view.candidates)
        H2hAbsenceCandidateDto(
          player: player(c.seat.userId),
          group: c.groupNumber,
          facts: facts(c.facts),
        ),
    ],
    moves: [
      for (final m in view.moves)
        H2hSeatMoveDto(
          id: m.id,
          kind: m.kind.wireName,
          fromRound: m.fromRound,
          out: player(m.outUser),
          into: player(m.inUser),
          eliteGroup: view.groupNumbers[m.eliteLeagueId] ?? 0,
          extraGroup: view.groupNumbers[m.extraLeagueId] ?? 0,
          absentRounds: [for (final r in m.absentRounds) r.round],
          createdAt: m.createdAt.toUtc().toIso8601String(),
          facts: m.facts == null ? null : facts(m.facts!),
          reason: m.reason,
          decidedBy: m.decidedBy == null ? null : player(m.decidedBy!),
        ),
    ],
  );
}

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
