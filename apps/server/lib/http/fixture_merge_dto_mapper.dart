import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// The wire shapes of a fixture's copies and of a merge (migration 0176,
/// script 95): `GET /admin/fixtures/{id}/copies` and
/// `POST /admin/fixtures/{id}/merge`.
FixtureCopiesDto fixtureCopiesToDto(List<FixtureCopy> copies) =>
    FixtureCopiesDto(
      copies: <FixtureCopyDto>[
        for (final c in copies)
          FixtureCopyDto(
            fixtureId: c.fixture.value,
            homeTeam: c.homeTeam,
            awayTeam: c.awayTeam,
            kickoffAt: c.kickoffAt.toUtc().toIso8601String(),
            hidden: c.hidden,
            predictions: c.predictions,
            doubles: c.doubles,
            hasResult: c.hasResult,
            linked: c.linked,
            isSelf: c.isSelf,
          ),
      ],
    );

/// [report] on the wire.
FixtureMergeReportDto fixtureMergeReportToDto(FixtureMergeReport report) =>
    FixtureMergeReportDto(
      moved: report.moved,
      doublesMoved: report.doublesMoved,
      doublesDropped: report.doublesDropped,
      bothPredicted: report.bothPredicted,
      late: report.late,
      notParticipant: report.notParticipant,
      linkMoved: report.linkMoved,
      keptHasResult: report.keptHasResult,
      applied: report.applied,
      rescored: report.rescored,
    );
