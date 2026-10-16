import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/index.dart' as correct_route;
// ignore: always_use_package_imports
import '../../routes/fixtures/index.dart' as register_route;
import 'competition_route_harness.dart';

const _hoffenheimId = 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1';
const _benficaId = 'e1e1e1e1-e1e1-4e1e-8e1e-e1e1e1e1e1e1';

/// `POST /fixtures` and `PUT /fixtures/{id}` as the server wires them
/// (script 93): a match that is not a test needs both its teams from the
/// catalog, refused 400 in Arabic otherwise; an older admin app that still
/// sends a typed name is told what to do.
void main() {
  final kickoff = DateTime.utc(2026, 10, 22, 19);

  ({CompositionRoot root, InMemoryFixtureScheduleRepository schedules})
  rootFor() {
    final schedules = InMemoryFixtureScheduleRepository();
    final clock = FixedClock(DateTime.utc(2026, 10, 16));
    final root = CompositionRoot.forTesting(
      registerFixtureSchedule: RegisterFixtureSchedule(
        repository: schedules,
        idGenerator: ScriptedIdGenerator([kFixtureId]),
        requireTeamIds: true,
      ),
      correctFixtureSchedule: CorrectFixtureSchedule(
        schedules,
        auditRecorder: AuditRecorder(
          auditLog: InMemoryAuditLogRepository(),
          idGenerator: ScriptedIdGenerator([kAuditEntryId]),
          clock: clock,
        ),
        clock: clock,
        requireTeamIds: true,
      ),
    );
    return (root: root, schedules: schedules);
  }

  test('POST without both team ids is 400 in Arabic, nothing stored', () async {
    final setup = rootFor();
    final response = await register_route.onRequest(
      wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {
          'home_team': 'هوفنهايم',
          'away_team': 'بيشتكاش',
          'kickoff_at': kickoff.toIso8601String(),
          'home_team_id': _hoffenheimId,
        },
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    final body = await decodeBody(response);
    expect(body['code'], RegisterFixtureSchedule.teamsRequiredCode);
    expect(body['message'], contains('قائمة الأندية'));
    expect(setup.schedules.count, 0);
  });

  test('POST with both team ids is 201', () async {
    final setup = rootFor();
    final response = await register_route.onRequest(
      wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {
          'home_team': 'هوفنهايم',
          'away_team': 'بنفيكا',
          'kickoff_at': kickoff.toIso8601String(),
          'home_team_id': _hoffenheimId,
          'away_team_id': _benficaId,
        },
      ),
    );

    expect(response.statusCode, HttpStatus.created);
    expect(setup.schedules.count, 1);
  });

  test('a test fixture may be posted with names only', () async {
    final setup = rootFor();
    final response = await register_route.onRequest(
      wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        body: {
          'home_team': 'فريق أ',
          'away_team': 'فريق ب',
          'kickoff_at': kickoff.toIso8601String(),
          'is_test': true,
        },
      ),
    );

    expect(response.statusCode, HttpStatus.created);
  });

  test('PUT without both team ids is 400, the stored fixture kept', () async {
    final setup = rootFor();
    await setup.schedules.upsert(
      FixtureSchedule.fromStored(
        fixture: const FixtureRef(kFixtureId),
        homeTeam: 'هوفنهايم',
        awayTeam: 'بيشتكاش',
        kickoffAt: kickoff,
      ),
    );

    final response = await correct_route.onRequest(
      wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: {
          'home_team': 'هوفنهايم',
          'away_team': 'بيشتكاش',
          'kickoff_at': kickoff.add(const Duration(hours: 1)).toIso8601String(),
          'home_team_id': _hoffenheimId,
        },
      ),
      kFixtureId,
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(
      (await decodeBody(response))['code'],
      RegisterFixtureSchedule.teamsRequiredCode,
    );
  });
}
