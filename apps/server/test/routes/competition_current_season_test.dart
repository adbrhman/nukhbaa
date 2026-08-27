import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/competitions/[id]/seasons/current.dart' as route;
import 'competition_route_harness.dart';

void main() {
  group('GET /competitions/{id}/seasons/current', () {
    late InMemoryCompetitionRepository repo;

    CompositionRoot rootWith({required DateTime now}) {
      repo = InMemoryCompetitionRepository();
      repo.competitions[kCompetitionId] = Competition.fromStored(
        id: (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value,
        name: 'Comp',
        format: FormatType.footballScoreline,
        visibility: CompetitionVisibility.public,
      );
      return CompositionRoot.forTesting(
        getCurrentSeason: GetCurrentSeason(
          repository: repo,
          clock: FixedClock(now),
        ),
      );
    }

    test('a season covering now returns 200 with the season', () async {
      repo = InMemoryCompetitionRepository();
      final root = rootWith(now: DateTime.utc(2026, 8, 15));
      repo.seasons[kSeasonId] = CompetitionSeason.fromStored(
        id: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
        competitionId:
            (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value,
        label: '08/2026',
        startAt: DateTime.utc(2026, 8),
        endAt: DateTime.utc(2026, 9),
      );

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['id'], kSeasonId);
      expect(body['competition_id'], kCompetitionId);
      expect(body['label'], '08/2026');
    });

    test('no season covers now returns 200 with a null body', () async {
      final root = rootWith(now: DateTime.utc(2026, 8, 15));

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.ok);
      expect(await response.body(), 'null');
    });

    test('a non-GET method is 405', () async {
      final root = rootWith(now: DateTime.utc(2026, 8, 15));

      final context = wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.post,
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
