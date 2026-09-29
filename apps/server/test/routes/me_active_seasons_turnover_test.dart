import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/active-seasons.dart' as route;
import 'competition_route_harness.dart';

const _october = 'c7300000-0000-4000-8000-000000000010';
const _participant = 'c7300000-0000-4000-8000-0000000000aa';

/// Five minutes into October, Riyadh time (00:05 on the 1st).
final DateTime _justAfterMidnight = DateTime.utc(2026, 9, 30, 21, 5);

CompetitionSeason _octoberSeason() => CompetitionSeason.fromStored(
  id: (SeasonId.tryParse(_october) as Ok<SeasonId>).value,
  competitionId:
      (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value,
  label: '10/2026',
  startAt: DateTime.utc(2026, 9, 30, 21),
  endAt: DateTime.utc(2026, 10, 31, 21),
);

(CompositionRoot, InMemoryCompetitionRepository) _world({
  required bool octoberHasFixtures,
}) {
  final repo = InMemoryCompetitionRepository();
  repo.competitions[kCompetitionId] = Competition.fromStored(
    id: (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value,
    name: 'Monthly',
    format: FormatType.footballScoreline,
    visibility: CompetitionVisibility.public,
  );
  final CompetitionSeason october = _octoberSeason();
  repo.seasons[_october] = october;
  if (octoberHasFixtures) {
    repo.openWithFixtures.add(october);
  }
  final root = CompositionRoot.forTesting(
    listMyActiveSeasons: ListMyActiveSeasons(
      competitionRepository: repo,
      clock: FixedClock(_justAfterMidnight),
    ),
    enrolInOpenSeasons: EnrolInOpenSeasons(
      competitionRepository: repo,
      idGenerator: ScriptedIdGenerator([_participant]),
    ),
  );
  return (root, repo);
}

Future<List<Object?>> _listOf(Response response) async =>
    jsonDecode(await response.body()) as List<Object?>;

void main() {
  group('GET /me/active-seasons at the month turnover', () {
    test('a player whose app stayed open across midnight lands in the new '
        'month', () async {
      final (root, repo) = _world(octoberHasFixtures: true);

      final response = await route.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final list = (await _listOf(response)).cast<Map<String, Object?>>();
      expect(list.single['season_id'], _october);
      expect(list.single['season_label'], '10/2026');
      expect(repo.participants.single.userId.value, kUserId);
    });

    test('asking twice enrols once', () async {
      final (root, repo) = _world(octoberHasFixtures: true);
      for (var i = 0; i < 2; i++) {
        await route.onRequest(
          wireContext(
            root: root,
            principal: userPrincipal(),
            method: HttpMethod.get,
          ),
        );
      }
      expect(repo.participants, hasLength(1));
    });

    test('a new month with no fixture yet enrols nobody', () async {
      final (root, repo) = _world(octoberHasFixtures: false);

      final response = await route.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(await _listOf(response), isEmpty);
      expect(repo.participants, isEmpty);
    });
  });
}
