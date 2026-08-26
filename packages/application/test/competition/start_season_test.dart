import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _adminId = '11111111-1111-1111-1111-111111111111';
const _competitionId = '22222222-2222-2222-2222-222222222222';
const _newSeasonId = '33333333-3333-3333-3333-333333333333';

Competition _competition() =>
    (Competition.create(
              id: const CompetitionId(_competitionId),
              name: 'Comp',
              format: FormatType.footballScoreline,
              visibility: CompetitionVisibility.public,
            )
            as Ok<Competition>)
        .value;

void main() {
  late FakeCompetitionRepository repo;
  late StartSeason useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    useCase = StartSeason(
      repository: repo,
      idGenerator: FakeIdGenerator([_newSeasonId]),
    );
  });

  test('admin starts the calendar-month season', () async {
    repo.seedCompetition(_competition());

    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: _competitionId,
      year: 2026,
      month: 8,
    );

    final season = (result as Ok<CompetitionSeason>).value;
    expect(season.id, const SeasonId(_newSeasonId));
    expect(season.competitionId, const CompetitionId(_competitionId));
    expect(season.label, '08/2026');
    expect(season.startAt, DateTime.utc(2026, 8, 1));
    expect(season.endAt, DateTime.utc(2026, 9, 1));
    expect((await repo.findSeason(const SeasonId(_newSeasonId))).isOk, isTrue);
  });

  test('rolls over correctly for December', () async {
    repo.seedCompetition(_competition());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: _competitionId,
      year: 2026,
      month: 12,
    );
    final season = (result as Ok<CompetitionSeason>).value;
    expect(season.startAt, DateTime.utc(2026, 12, 1));
    expect(season.endAt, DateTime.utc(2027, 1, 1));
    expect(season.label, '12/2026');
  });

  test('non-admin is rejected', () async {
    repo.seedCompetition(_competition());
    final result = await useCase(
      principal: userPrincipal(_adminId),
      competitionId: _competitionId,
      year: 2026,
      month: 8,
    );
    expect(
      (result as Err<CompetitionSeason>).error.kind,
      ErrorKind.authorization,
    );
  });

  test('a malformed competition id is a validation error', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: 'not-a-uuid',
      year: 2026,
      month: 8,
    );
    expect(
      (result as Err<CompetitionSeason>).error.code,
      'competition.competition_id_malformed',
    );
  });

  test('a missing competition is invariant not_found', () async {
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: _competitionId,
      year: 2026,
      month: 8,
    );
    final error = (result as Err<CompetitionSeason>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.not_found');
  });

  test('an out-of-range month is rejected', () async {
    repo.seedCompetition(_competition());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: _competitionId,
      year: 2026,
      month: 13,
    );
    expect(
      (result as Err<CompetitionSeason>).error.code,
      'competition.season_month_invalid',
    );
  });

  test('an out-of-range year is rejected', () async {
    repo.seedCompetition(_competition());
    final result = await useCase(
      principal: adminPrincipal(_adminId),
      competitionId: _competitionId,
      year: 1999,
      month: 8,
    );
    expect(
      (result as Err<CompetitionSeason>).error.code,
      'competition.season_year_invalid',
    );
  });
}
