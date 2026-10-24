import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/leagues/index.dart' as route;
import 'competition_route_harness.dart';

const _leagueId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

/// A catalog with one league on file, `ديربيات كبرى`, keyed as the adapter
/// keys names (spaces and alif maqsura folded, enough for these cases).
final class _Catalog implements LeagueCatalogWriter {
  int writes = 0;
  String? name;

  static String _key(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').replaceAll('ى', 'ي');

  @override
  Future<Result<LeagueAddition>> add({required String name}) async {
    if (_key(name) == _key('ديربيات كبرى')) {
      return const Result.ok(
        LeagueAddition(
          league: League(
            id: LeagueRef('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
            name: 'ديربيات كبرى',
            shortName: 'DRB',
            logoUrl: null,
            isContinental: true,
          ),
          existed: true,
        ),
      );
    }
    writes++;
    this.name = name;
    return Result.ok(
      LeagueAddition(
        league: League(
          id: const LeagueRef(_leagueId),
          name: name,
          shortName: null,
          logoUrl: null,
          isContinental: true,
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
    adminAddLeague: AdminAddLeague(
      writer: catalog,
      auditRecorder: AuditRecorder(
        auditLog: audit,
        idGenerator: ScriptedIdGenerator([
          '99999999-9999-4999-8999-999999999999',
        ]),
        clock: FixedClock(DateTime.utc(2026, 10, 24, 13)),
      ),
    ),
  );
  return (root: root, catalog: catalog, audit: audit);
}

/// `POST /admin/leagues` (script 139, migration 0183).
void main() {
  test('an admin adds a league: 201 with the league, continental, '
      'audited', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': ' كأس السوبر الأفريقي '},
      ),
    );

    expect(response.statusCode, HttpStatus.created);
    final body = await decodeBody(response);
    expect(body['id'], _leagueId);
    expect(body['name'], 'كأس السوبر الأفريقي');
    expect(body['is_continental'], isTrue);
    expect(body['logo_url'], isNull);
    expect(built.catalog.name, 'كأس السوبر الأفريقي');
    expect(built.audit.entries.single.action, AuditAction.leagueAdded);
    expect(built.audit.entries.single.targetRef, _leagueId);
  });

  test('a league already on file is 409 in Arabic, naming it; nothing '
      'written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 'ديربيات  كبري'},
      ),
    );

    expect(response.statusCode, HttpStatus.conflict);
    final body = await decodeBody(response);
    expect(body['code'], 'football_data.league_exists');
    expect(body['message'], contains('«ديربيات كبرى»'));
    expect(built.catalog.writes, 0);
    expect(built.audit.entries, isEmpty);
  });

  test('a missing name is 400, nothing written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const <String, Object?>{},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(built.catalog.writes, 0);
  });

  test('a name of the wrong type is 400, nothing written', () async {
    final built = _root();
    final response = await route.onRequest(
      wireContext(
        root: built.root,
        principal: adminPrincipal(),
        body: const {'name': 7},
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
        body: const {'name': 'دوري جديد'},
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
