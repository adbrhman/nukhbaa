import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a relative
// import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/competitions/[id]/seasons/index.dart' as seasons_route;
import 'competition_route_harness.dart';

/// Route tests for the season *browse* read surface added under the FA-1
/// scope closure (2026-07-13): the `GET` branch of
/// `GET /competitions/{id}/seasons` (added beside the untouched `POST` command
/// branch). The round read it once covered is gone (script 98).
///
/// Tested through the real wiring (`context.read<Future<CompositionRoot>>()` →
/// `root.listCompetitionSeasons()`) over the
/// in-memory [InMemoryCompetitionRepository], mirroring `rounds_browse_test.dart`
/// / `competitions_browse_test.dart` — edge → use-case → domain → port.
///
/// Auth note: a "no bearer token → 401" case is deliberately NOT tested here —
/// that refusal is the `bearerAuth` middleware's job (the `/competitions` and
/// `/seasons` subtrees apply it via their `_middleware.dart`), before the
/// handler runs; the handler is only reached WITH a principal, mirrored by
/// `wireContext` requiring one. Both reads gate on `PlatformRole.user`, which
/// every authenticated principal satisfies, so neither browse read produces
/// `auth.insufficient_role`.
void main() {
  final competitionId =
      (CompetitionId.tryParse(kCompetitionId) as Ok<CompetitionId>).value;

  /// A stored season under the canonical competition, keyed by its own id.
  CompetitionSeason season(String id, String label) =>
      CompetitionSeason.fromStored(
        id: (SeasonId.tryParse(id) as Ok<SeasonId>).value,
        competitionId: competitionId,
        label: label,
        startAt: DateTime.utc(2026, 8, 1),
        endAt: DateTime.utc(2026, 9, 1),
      );

  group('GET /competitions/{id}/seasons (browse list)', () {
    late InMemoryCompetitionRepository repo;

    CompositionRoot rootWith() {
      repo = InMemoryCompetitionRepository();
      return CompositionRoot.forTesting(
        listCompetitionSeasons: ListCompetitionSeasons(repository: repo),
      );
    }

    test(
      'returns 200 with the competition seasons, label-then-id ordered',
      () async {
        final root = rootWith();
        // Seeded out of order to prove the ORDER BY label ASC, id ASC.
        final b = season('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '2026/27');
        final a = season('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2025/26');
        repo.seasons[b.id.value] = b;
        repo.seasons[a.id.value] = a;

        final context = wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        );

        final response = await seasons_route.onRequest(context, kCompetitionId);

        expect(response.statusCode, HttpStatus.ok);
        final body = await response.json() as List<Object?>;
        final items = body.cast<Map<String, Object?>>();
        expect(items, hasLength(2));
        // '2025/26' sorts before '2026/27'.
        expect(items[0]['label'], '2025/26');
        expect(items[1]['label'], '2026/27');
        // Shape is the versioned SeasonDto.
        expect(items[0]['schema_version'], 2);
        expect(items[0]['id'], 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
        expect(items[0]['competition_id'], kCompetitionId);
      },
    );

    test('a competition with no seasons is a legitimate 200 empty array (no '
        'existence oracle)', () async {
      final context = wireContext(
        root: rootWith(),
        principal: userPrincipal(),
        method: HttpMethod.get,
      );

      // Nothing seeded — a browse read reveals no existence oracle, so an
      // absent/empty competition is an empty list, never a 404.
      final response = await seasons_route.onRequest(
        context,
        '44444444-4444-4444-4444-444444444444',
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      expect(body, isEmpty);
    });

    test('an unsupported method (DELETE) is 405', () async {
      final context = wireContext(
        root: rootWith(),
        principal: userPrincipal(),
        method: HttpMethod.delete,
      );

      final response = await seasons_route.onRequest(context, kCompetitionId);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
