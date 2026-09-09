import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fake_competition_repository.dart';
import 'fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _monthlyCompetition = '11111111-1111-1111-1111-111111111111';
const _leagueCompetition = '22222222-2222-2222-2222-222222222222';
const _september = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _october = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _leagueEdition = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

CompetitionSeason _season({
  required String id,
  required String competitionId,
  required String label,
  required DateTime startAt,
}) => CompetitionSeason.fromStored(
  id: SeasonId(id),
  competitionId: CompetitionId(competitionId),
  label: label,
  startAt: startAt,
  endAt: startAt.add(const Duration(days: 30)),
);

void main() {
  late FakeCompetitionRepository repo;
  late ListMonthlySeasons useCase;

  setUp(() {
    repo = FakeCompetitionRepository();
    useCase = ListMonthlySeasons(repository: repo);
  });

  test(
    'lists the months newest first, whatever order they were filed',
    () async {
      // Seeded oldest-last on purpose: the ordering must come from the read.
      repo.seedSeason(
        _season(
          id: _september,
          competitionId: _monthlyCompetition,
          label: '09/2026',
          startAt: DateTime.utc(2026, 9),
        ),
      );
      repo.seedSeason(
        _season(
          id: _october,
          competitionId: _monthlyCompetition,
          label: '10/2026',
          startAt: DateTime.utc(2026, 10),
        ),
      );

      final r = await useCase.call(principal: userPrincipal(_user));

      final labels = [
        for (final s in (r as Ok<List<CompetitionSeason>>).value) s.label,
      ];
      expect(labels, ['10/2026', '09/2026']);
    },
  );

  test('a league edition is not a month, however open its window', () async {
    // The whole reason the rule reads the LABEL and not the window: the
    // seeded league seasons carry a current-month window too, and eight of
    // them would drown the one month the admin is actually looking for.
    repo.seedSeason(
      _season(
        id: _leagueEdition,
        competitionId: _leagueCompetition,
        label: '2026/27',
        startAt: DateTime.utc(2026, 9),
      ),
    );
    repo.seedSeason(
      _season(
        id: _september,
        competitionId: _monthlyCompetition,
        label: '09/2026',
        startAt: DateTime.utc(2026, 9),
      ),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    final ids = [
      for (final s in (r as Ok<List<CompetitionSeason>>).value) s.id.value,
    ];
    expect(ids, [_september]);
  });

  test('no month opened yet is an empty list, not an error', () async {
    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Ok<List<CompetitionSeason>>).value, isEmpty);
  });

  test('a repository failure propagates untranslated', () async {
    repo.failNextWith(
      const AppError.transient('db.unavailable', 'connection refused'),
    );

    final r = await useCase.call(principal: userPrincipal(_user));

    expect((r as Err<List<CompetitionSeason>>).error.code, 'db.unavailable');
  });
}
