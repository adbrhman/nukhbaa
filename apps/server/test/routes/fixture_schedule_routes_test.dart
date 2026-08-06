import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/fixtures/index.dart' as register_route;
// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/index.dart' as correct_route;
import 'competition_route_harness.dart';

/// Route tests for the fixture-IDENTITY seam — `POST /fixtures`
/// (`RegisterFixtureSchedule`) and `PUT /fixtures/{id}`
/// (`CorrectFixtureSchedule`).
///
/// This is the coverage gap flagged during the Phase-0 code audit: every
/// other route subtree (admin, scoring, ledger, social, ...) has a matching
/// test file; `/fixtures` (registration/correction side, as opposed to
/// `/fixtures/{id}/result`, which IS covered by `scoring_routes_test.dart`)
/// did not.
///
/// Like `scoring_routes_test.dart`, these exercise the *real* wiring
/// (`context.read<Future<CompositionRoot>>()` → `root.<useCase>()`) over the
/// in-memory [InMemoryFixtureScheduleRepository], so the assertions cover the
/// edge → use-case → domain → port path end-to-end, hermetically. It is NOT a
/// substitute for the Postgres adapter's own tests (infrastructure package) or
/// the use-cases'/domain's own tests (application/domain packages): its job is
/// the routes' status mapping, DTO shaping, admin gating, and body validation
/// surfaced across the HTTP boundary.
void main() {
  // A second, distinct fixture id for the "correct an unregistered id"
  // upsert-semantics test, so it never collides with the harness's canonical
  // kFixtureId.
  const kUnregisteredFixtureId = 'dcdcdcdc-dcdc-dcdc-dcdc-dcdcdcdcdcdc';

  final kickoff = DateTime.utc(2026, 9, 1, 18, 30);

  // ---------------------------------------------------------------------------
  // POST /fixtures — RegisterFixtureSchedule (admin-only, server-generated id)
  // ---------------------------------------------------------------------------
  group('POST /fixtures', () {
    ({CompositionRoot root, InMemoryFixtureScheduleRepository schedules})
    rootFor() {
      final schedules = InMemoryFixtureScheduleRepository();
      final root = CompositionRoot.forTesting(
        registerFixtureSchedule: RegisterFixtureSchedule(
          repository: schedules,
          idGenerator: ScriptedIdGenerator([kFixtureId]),
        ),
      );
      return (root: root, schedules: schedules);
    }

    Future<Response> post(
      CompositionRoot root,
      AuthenticatedUser principal, {
      Object? body,
    }) => register_route.onRequest(
      wireContext(
        root: root,
        principal: principal,
        method: HttpMethod.post,
        body:
            body ??
            {
              'home_team': 'Al Hilal',
              'away_team': 'Al Nassr',
              'kickoff_at': kickoff.toIso8601String(),
            },
      ),
    );

    test(
      'an admin registers a fixture and gets 201 with the server-generated id',
      () async {
        final setup = rootFor();
        final response = await post(setup.root, adminPrincipal());

        expect(response.statusCode, HttpStatus.created);
        final body = await decodeBody(response);
        expect(body['fixture_id'], kFixtureId);
        expect(body['home_team'], 'Al Hilal');
        expect(body['away_team'], 'Al Nassr');
        expect(body['kickoff_at'], kickoff.toIso8601String());
        // The identity was actually persisted behind the seam.
        final stored = await setup.schedules.findByFixture(
          (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
        );
        final value = (stored as Ok<FixtureSchedule?>).value!;
        expect(value.homeTeam, 'Al Hilal');
        expect(value.awayTeam, 'Al Nassr');
        expect(setup.schedules.count, 1);
      },
    );

    test('team names are trimmed before storage and on the wire', () async {
      final setup = rootFor();
      final response = await post(
        setup.root,
        adminPrincipal(),
        body: {
          'home_team': '  Al Hilal  ',
          'away_team': '  Al Nassr  ',
          'kickoff_at': kickoff.toIso8601String(),
        },
      );

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['home_team'], 'Al Hilal');
      expect(body['away_team'], 'Al Nassr');
    });

    test('a non-admin caller is rejected 401 (admin-only gate)', () async {
      final setup = rootFor();
      final response = await post(setup.root, userPrincipal());

      expect(response.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(response))['code'], 'auth.insufficient_role');
      // Nothing was written on the rejected path.
      expect(setup.schedules.count, 0);
    });

    test('a missing home_team is rejected 400 request.field_missing', () async {
      final setup = rootFor();
      final response = await post(
        setup.root,
        adminPrincipal(),
        body: {'away_team': 'Al Nassr', 'kickoff_at': kickoff.toIso8601String()},
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'request.field_missing');
      expect(setup.schedules.count, 0);
    });

    test('a missing away_team is rejected 400 request.field_missing', () async {
      final setup = rootFor();
      final response = await post(
        setup.root,
        adminPrincipal(),
        body: {'home_team': 'Al Hilal', 'kickoff_at': kickoff.toIso8601String()},
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'request.field_missing');
      expect(setup.schedules.count, 0);
    });

    test(
      'a missing kickoff_at is rejected 400 request.field_missing',
      () async {
        final setup = rootFor();
        final response = await post(
          setup.root,
          adminPrincipal(),
          body: {'home_team': 'Al Hilal', 'away_team': 'Al Nassr'},
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect((await decodeBody(response))['code'], 'request.field_missing');
        expect(setup.schedules.count, 0);
      },
    );

    test(
      'a malformed kickoff_at is rejected 400 request.kickoff_malformed',
      () async {
        final setup = rootFor();
        final response = await post(
          setup.root,
          adminPrincipal(),
          body: {
            'home_team': 'Al Hilal',
            'away_team': 'Al Nassr',
            'kickoff_at': 'not-a-date',
          },
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          (await decodeBody(response))['code'],
          'request.kickoff_malformed',
        );
        expect(setup.schedules.count, 0);
      },
    );

    test(
      'identical home/away team names are rejected 400 '
      'competition.fixture_schedule_same_team (domain validation)',
      () async {
        final setup = rootFor();
        final response = await post(
          setup.root,
          adminPrincipal(),
          body: {
            'home_team': 'Al Hilal',
            'away_team': 'al hilal', // case-insensitive match, per domain rule
            'kickoff_at': kickoff.toIso8601String(),
          },
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          (await decodeBody(response))['code'],
          'competition.fixture_schedule_same_team',
        );
        expect(setup.schedules.count, 0);
      },
    );

    test(
      'a team name over 120 characters is rejected 400 '
      'competition.fixture_schedule_team_len',
      () async {
        final setup = rootFor();
        final response = await post(
          setup.root,
          adminPrincipal(),
          body: {
            'home_team': 'A' * 121,
            'away_team': 'Al Nassr',
            'kickoff_at': kickoff.toIso8601String(),
          },
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          (await decodeBody(response))['code'],
          'competition.fixture_schedule_team_len',
        );
        expect(setup.schedules.count, 0);
      },
    );

    test('a non-POST method is 405', () async {
      final setup = rootFor();
      final response = await register_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  // ---------------------------------------------------------------------------
  // PUT /fixtures/{id} — CorrectFixtureSchedule (admin-only, path-supplied id)
  // ---------------------------------------------------------------------------
  group('PUT /fixtures/{id}', () {
    ({CompositionRoot root, InMemoryFixtureScheduleRepository schedules})
    rootFor() {
      final schedules = InMemoryFixtureScheduleRepository();
      final root = CompositionRoot.forTesting(
        correctFixtureSchedule: CorrectFixtureSchedule(schedules),
      );
      return (root: root, schedules: schedules);
    }

    Future<Response> put(
      CompositionRoot root,
      AuthenticatedUser principal,
      String id, {
      Object? body,
    }) => correct_route.onRequest(
      wireContext(
        root: root,
        principal: principal,
        method: HttpMethod.put,
        body:
            body ??
            {
              'home_team': 'Al Hilal',
              'away_team': 'Al Nassr',
              'kickoff_at': kickoff.toIso8601String(),
            },
      ),
      id,
    );

    test(
      'an admin corrects an already-registered fixture and gets 200 with '
      'the updated identity, one stored row (upsert in place)',
      () async {
        final setup = rootFor();
        await setup.schedules.upsert(
          (FixtureSchedule.create(
                    fixture:
                        (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>)
                            .value,
                    homeTeam: 'Al Hilal (mistyped)',
                    awayTeam: 'Al Nassr',
                    kickoffAt: kickoff,
                  )
                  as Ok<FixtureSchedule>)
              .value,
        );

        final corrected = kickoff.add(const Duration(hours: 1));
        final response = await put(
          setup.root,
          adminPrincipal(),
          kFixtureId,
          body: {
            'home_team': 'Al Hilal',
            'away_team': 'Al Nassr',
            'kickoff_at': corrected.toIso8601String(),
          },
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['fixture_id'], kFixtureId);
        expect(body['home_team'], 'Al Hilal');
        expect(body['kickoff_at'], corrected.toIso8601String());
        expect(setup.schedules.count, 1);
      },
    );

    test(
      'correcting an unregistered id upserts it — the same idempotent-upsert '
      'contract as fixture-result recording (Next-Task decision 2026-07-11, '
      'option (a))',
      () async {
        final setup = rootFor();
        final response = await put(
          setup.root,
          adminPrincipal(),
          kUnregisteredFixtureId,
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['fixture_id'], kUnregisteredFixtureId);
        expect(setup.schedules.count, 1);
      },
    );

    test('a non-admin caller is rejected 401 (admin-only gate)', () async {
      final setup = rootFor();
      final response = await put(setup.root, userPrincipal(), kFixtureId);

      expect(response.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(response))['code'], 'auth.insufficient_role');
      expect(setup.schedules.count, 0);
    });

    test('a missing home_team is rejected 400 request.field_missing', () async {
      final setup = rootFor();
      final response = await put(
        setup.root,
        adminPrincipal(),
        kFixtureId,
        body: {'away_team': 'Al Nassr', 'kickoff_at': kickoff.toIso8601String()},
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'request.field_missing');
      expect(setup.schedules.count, 0);
    });

    test(
      'identical home/away team names are rejected 400 '
      'competition.fixture_schedule_same_team (domain validation)',
      () async {
        final setup = rootFor();
        final response = await put(
          setup.root,
          adminPrincipal(),
          kFixtureId,
          body: {
            'home_team': 'Al Hilal',
            'away_team': 'Al Hilal',
            'kickoff_at': kickoff.toIso8601String(),
          },
        );

        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          (await decodeBody(response))['code'],
          'competition.fixture_schedule_same_team',
        );
        expect(setup.schedules.count, 0);
      },
    );

    test('a non-PUT method is 405', () async {
      final setup = rootFor();
      final response = await correct_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        kFixtureId,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
