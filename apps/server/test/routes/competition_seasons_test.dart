import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/competitions/[id]/seasons/index.dart' as route;
import 'competition_route_harness.dart';

void main() {
  group('POST /competitions/{id}/seasons', () {
    late InMemoryCompetitionRepository repo;

    CompositionRoot rootWith({bool withCompetition = true}) {
      repo = InMemoryCompetitionRepository();
      if (withCompetition) {
        repo.competitions[kCompetitionId] = Competition.fromStored(
          id: (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>)
              .value,
          name: 'Comp',
          format: FormatType.footballScoreline,
          visibility: CompetitionVisibility.public,
        );
      }
      return CompositionRoot.forTesting(
        startSeason: StartSeason(
          repository: repo,
          idGenerator: ScriptedIdGenerator([kSeasonId]),
        ),
      );
    }

    test('starts the calendar-month season and returns 201', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'year': 2026, 'month': 8},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['id'], kSeasonId);
      expect(body['competition_id'], kCompetitionId);
      expect(body['label'], '08/2026');
      expect(body['start_at'], '2026-08-01T00:00:00.000Z');
      expect(body['end_at'], '2026-09-01T00:00:00.000Z');
      expect(repo.seasons[kSeasonId], isNotNull);
    });

    test('a missing competition surfaces as 409 not_found', () async {
      final context = wireContext(
        root: rootWith(withCompetition: false),
        principal: adminPrincipal(),
        body: const {'year': 2026, 'month': 8},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'competition.not_found');
    });

    test('a non-admin principal is rejected with 401', () async {
      final context = wireContext(
        root: rootWith(),
        principal: userPrincipal(),
        body: const {'year': 2026, 'month': 8},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('a missing year field is 400', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'month': 8},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('a missing month field is 400', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'year': 2026},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('an out-of-range month is 400', () async {
      final context = wireContext(
        root: rootWith(),
        principal: adminPrincipal(),
        body: const {'year': 2026, 'month': 13},
      );

      final response = await route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });
}
