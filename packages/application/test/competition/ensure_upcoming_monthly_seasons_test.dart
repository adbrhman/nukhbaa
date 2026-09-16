import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _monthly = '11111111-1111-1111-1111-111111111111';
const _ids = [
  'a0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000003',
  'a0000000-0000-0000-0000-000000000004',
];

CompetitionSeason _month(
  String id,
  int year,
  int month,
) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: const CompetitionId(_monthly),
  label:
      '${month.toString().padLeft(2, '0')}/${year.toString().padLeft(4, '0')}',
  startAt: DateTime.utc(year, month),
  endAt: DateTime.utc(year, month + 1),
);

// The fake repository, like the database, refuses a season whose
// competition does not exist.
Competition _competition() =>
    (Competition.create(
              id: const CompetitionId(_monthly),
              name: 'Monthly contest',
              format: FormatType.footballScoreline,
              visibility: CompetitionVisibility.public,
            )
            as Ok<Competition>)
        .value;

Future<List<CompetitionSeason>> _monthlySeasons(
  FakeCompetitionRepository repo,
) async =>
    ((await repo.listMonthlySeasons()) as Ok<List<CompetitionSeason>>).value;

void main() {
  late FakeCompetitionRepository repo;
  late EnsureUpcomingMonthlySeasons useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    repo.seedCompetition(_competition());
    useCase = EnsureUpcomingMonthlySeasons(
      repository: repo,
      idGenerator: FakeIdGenerator(_ids),
    );
    repo
      ..seedSeason(_month('b0000000-0000-0000-0000-000000000009', 2026, 9))
      ..seedSeason(_month('b0000000-0000-0000-0000-000000000010', 2026, 10));
  });

  test('does nothing while the next month is more than a week away', () async {
    final result = await useCase.call(now: DateTime.utc(2026, 10, 20));

    expect((result as Ok<int>).value, 0);
    expect(await _monthlySeasons(repo), hasLength(2));
  });

  test('creates next month a week ahead, in the same competition', () async {
    final result = await useCase.call(now: DateTime.utc(2026, 10, 26));

    expect((result as Ok<int>).value, 1);
    final newest = (await _monthlySeasons(repo)).first;
    expect(newest.label, '11/2026');
    expect(newest.competitionId, const CompetitionId(_monthly));
    expect(newest.startAt, DateTime.utc(2026, 11));
    expect(newest.endAt, DateTime.utc(2026, 12));
  });

  test('is idempotent: a second run creates nothing more', () async {
    await useCase.call(now: DateTime.utc(2026, 10, 26));
    final second = await useCase.call(now: DateTime.utc(2026, 10, 26, 6));

    expect((second as Ok<int>).value, 0);
    expect(await _monthlySeasons(repo), hasLength(3));
  });

  test('crosses the year boundary', () async {
    repo
      ..seedSeason(_month('b0000000-0000-0000-0000-000000000011', 2026, 11))
      ..seedSeason(_month('b0000000-0000-0000-0000-000000000012', 2026, 12));

    final result = await useCase.call(now: DateTime.utc(2026, 12, 28));

    expect((result as Ok<int>).value, 1);
    final newest = (await _monthlySeasons(repo)).first;
    expect(newest.label, '01/2027');
    expect(newest.startAt, DateTime.utc(2027));
    expect(newest.endAt, DateTime.utc(2027, 2));
  });

  test('catches up after a long outage, at most three months a run', () async {
    final result = await useCase.call(now: DateTime.utc(2027, 3, 10));

    expect((result as Ok<int>).value, 3);
    expect((await _monthlySeasons(repo)).map((s) => s.label).take(3), [
      '01/2027',
      '12/2026',
      '11/2026',
    ]);
  });

  test('with no monthly season there is nothing to follow', () async {
    final empty = FakeCompetitionRepository();
    final result = await EnsureUpcomingMonthlySeasons(
      repository: empty,
      idGenerator: FakeIdGenerator(_ids),
    ).call(now: DateTime.utc(2026, 10, 30));

    expect((result as Ok<int>).value, 0);
  });

  test('a repository failure is returned unchanged', () async {
    const failure = AppError.transient('db.down', 'down');
    repo.failNextWith(failure);

    final result = await useCase.call(now: DateTime.utc(2026, 10, 26));

    expect((result as Err<int>).error, failure);
  });
}
