import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/teams/index.dart' as route;
import 'competition_route_harness.dart';

const _teamId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _leagueId = 'abababab-abab-4bab-8bab-abababababab';

/// A catalog with one club on file, `بشكتاش`, keyed as the adapter keys
/// names (spaces and taa marbuta folded, enough for these cases).
final class _Catalog implements TeamCatalogWriter {
  int writes = 0;
  String? name;
  LeagueRef? leagueId;

  static String _key(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').replaceAll('ة', 'ه');

  @override
  Future<Result<TeamAddition>> add({
    required String name,
    required LeagueRef? leagueId,
  }) async {
    if (_key(name) == _key('بشكتاش')) {
      return const Result.ok(
        TeamAddition(
          team: Team(
            id: TeamRef('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
            name: 'بشكتاش',
            shortName: null,
            crestUrl: null,
          ),
          existed: true,
        ),
      );
    }
    writes++;
    this.name = name;
    this.leagueId = leagueId;
    return Result.ok(
      TeamAddition(
        team: Team(
          id: const TeamRef(_teamId),
          name: name,
          shortName: null,
          crestUrl: null,
          leagueId: leagueId,
        ),
        existed: false,
      ),
    );
  }
}

({CompositionRoot root, _Catalog catalog, InMemoryAuditLogRepository audit})
_root() {
  final catalog = _Catalog();
  final audit = InMemoryAuditLogRepository();
  final root = CompositionRoot.forTesting(
    adminAddTeam: AdminAddTeam(
      writer: catalog,
      auditRecorder: AuditRecorder(
        auditLog: audit,
        idGenerator: ScriptedIdGenerator([
          '99999999-9999-4999-8999-999999999999',
        ]),
        clock: FixedClock(DateTime.utc(2026, 10, 16, 13)),
      ),
    ),
  );
  return (root: root, catalog: catalog, audit: audit);
}

/// `POST /admin/teams` (script 91, migration 0173).
void main() {
  test('an admin adds a club under a league: 201 with the club, '
      'audited', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 'نادي جديد', 'league_id': _leagueId},
      ),
    );

    expect(response.statusCode, HttpStatus.created);
    final body = await decodeBody(response);
    expect(body['id'], _teamId);
    expect(body['name'], 'نادي جديد');
    expect(body['league_id'], _leagueId);
    expect(body['crest_url'], isNull);
    expect(built.catalog.leagueId?.value, _leagueId);
    expect(built.audit.entries.single.action, AuditAction.teamAdded);
    expect(built.audit.entries.single.targetRef, _teamId);
  });

  test('without a league the club is filed under none', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 'نادي جديد'},
      ),
    );

    expect(response.statusCode, HttpStatus.created);
    expect((await decodeBody(response))['league_id'], isNull);
    expect(built.catalog.leagueId, isNull);
  });

  test('a club already on file is 409 in Arabic, naming it; nothing '
      'written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 'بشكتاش '},
      ),
    );

    expect(response.statusCode, HttpStatus.conflict);
    final body = await decodeBody(response);
    expect(body['code'], 'football_data.team_exists');
    expect(body['message'], contains('«بشكتاش»'));
    expect(built.catalog.writes, 0);
    expect(built.audit.entries, isEmpty);
  });

  test('a missing name is 400, nothing written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'league_id': _leagueId},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(built.catalog.writes, 0);
  });

  test('a league id of the wrong type is 400, nothing written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 'نادي جديد', 'league_id': 7},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(built.catalog.writes, 0);
  });

  test('a player is refused, nothing written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: userPrincipal(),
        body: const {'name': 'نادي جديد'},
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(built.catalog.writes, 0);
  });

  test('only POST', () async {
    final response = await route.onRequest(
      wireContext(
        root: _root().root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
