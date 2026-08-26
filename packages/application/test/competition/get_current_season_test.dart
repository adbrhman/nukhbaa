import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _competition = '22222222-2222-2222-2222-222222222222';
const _otherCompetition = '99999999-9999-9999-9999-999999999999';
const _seasonAug = '55555555-5555-5555-5555-555555555555';
const _seasonSep = '66666666-6666-6666-6666-666666666666';

final _now = DateTime.utc(2026, 8, 15);

CompetitionSeason _season({
  required String id,
  required String competitionId,
  required DateTime startAt,
  required DateTime endAt,
}) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: CompetitionId(competitionId),
  label: 'x',
  startAt: startAt,
  endAt: endAt,
);

void main() {
  late FakeCompetitionRepository repo;
  late GetCurrentSeason useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    useCase = GetCurrentSeason(repository: repo, clock: FixedClock(_now));
  });

  test('resolves the season whose window covers "now"', () async {
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    final season = (r as Ok<CompetitionSeason?>).value;
    expect(season?.id.value, _seasonAug);
  });

  test(
    'a month with no season yet is a legitimate Ok(null), not an error',
    () async {
      // Only a future season exists; "now" falls in the gap before it.
      repo.seedSeason(
        _season(
          id: _seasonSep,
          competitionId: _competition,
          startAt: DateTime.utc(2026, 9),
          endAt: DateTime.utc(2026, 10),
        ),
      );

      final r = await useCase.call(
        principal: userPrincipal(_user),
        competitionId: _competition,
      );

      expect(r, isA<Ok<CompetitionSeason?>>());
      expect((r as Ok<CompetitionSeason?>).value, isNull);
    },
  );

  test('only the requested competition\'s seasons are considered', () async {
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _otherCompetition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    expect((r as Ok<CompetitionSeason?>).value, isNull);
  });

  test('an overlap between two seasons resolves to the earliest startAt', () {
    // Documents the port's tie-break for the known (unconstrained) overlap
    // gap -- exercised directly against the fake to pin the contract.
    repo.seedSeason(
      _season(
        id: _seasonSep,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8, 10),
        endAt: DateTime.utc(2026, 9, 10),
      ),
    );
    repo.seedSeason(
      _season(
        id: _seasonAug,
        competitionId: _competition,
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      ),
    );

    expect(
      repo
          .findCurrentSeason(
            competitionId: const CompetitionId(_competition),
            nowUtc: _now,
          )
          .then((r) => (r as Ok<CompetitionSeason?>).value?.id.value),
      completion(_seasonAug),
    );
  });

  test('a malformed competition id is a validation error', () async {
    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: 'not-a-uuid',
    );

    expect((r as Err<CompetitionSeason?>).error.kind, ErrorKind.validation);
  });

  test('a transient repository failure is propagated unchanged', () async {
    repo.failNextWith(
      const AppError.transient('db.unavailable', 'connection reset'),
    );

    final r = await useCase.call(
      principal: userPrincipal(_user),
      competitionId: _competition,
    );

    final err = (r as Err<CompetitionSeason?>).error;
    expect(err.kind, ErrorKind.transient);
    expect(err.code, 'db.unavailable');
  });
}
