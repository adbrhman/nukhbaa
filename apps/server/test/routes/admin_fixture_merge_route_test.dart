import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/fixtures/[id]/copies/index.dart' as copies_route;
// ignore: always_use_package_imports
import '../../routes/admin/fixtures/[id]/merge/index.dart' as merge_route;
import 'competition_route_harness.dart';

const _copy = 'fde6264d-0000-4000-8000-000000000001';
const _kept = 'a2e41db8-0000-4000-8000-000000000001';

/// Answers what the database would and records every call.
final class _Merger implements FixtureMerger {
  _Merger({this.refusal});

  final AppError? refusal;
  final List<bool> applies = [];

  @override
  Future<Result<FixtureMergeReport>> merge({
    required FixtureRef duplicate,
    required FixtureRef kept,
    required UserId actor,
    required bool apply,
  }) async {
    applies.add(apply);
    final e = refusal;
    if (e != null) return Result.err(e);
    return Result.ok(
      FixtureMergeReport(
        moved: 3,
        doublesMoved: 1,
        doublesDropped: 1,
        bothPredicted: 1,
        late: 0,
        notParticipant: 0,
        linkMoved: true,
        keptHasResult: true,
        applied: apply,
      ),
    );
  }

  @override
  Future<Result<List<FixtureCopy>>> copiesOf(FixtureRef fixture) async =>
      Result.ok([
        FixtureCopy(
          fixture: fixture,
          homeTeam: 'سالزبورغ',
          awayTeam: 'ميلان',
          kickoffAt: DateTime.utc(2026, 10, 15, 19),
          hidden: true,
          predictions: 3,
          doubles: 0,
          hasResult: false,
          linked: false,
          isSelf: true,
        ),
        FixtureCopy(
          fixture: const FixtureRef(_kept),
          homeTeam: 'سالزبورغ',
          awayTeam: 'ميلان',
          kickoffAt: DateTime.utc(2026, 10, 15, 19),
          hidden: false,
          predictions: 41,
          doubles: 6,
          hasResult: true,
          linked: true,
          isSelf: false,
        ),
      ]);
}

({CompositionRoot root, _Merger merger, List<String> rescored}) _root({
  AppError? refusal,
}) {
  final merger = _Merger(refusal: refusal);
  final rescored = <String>[];
  Future<Result<void>> rescore({required String fixtureId}) async {
    rescored.add(fixtureId);
    return const Result.ok(null);
  }

  final root = CompositionRoot.forTesting(
    adminListFixtureCopies: AdminListFixtureCopies(merger: merger),
    adminMergeFixtureCopies: AdminMergeFixtureCopies(
      merger: merger,
      rescore: rescore,
    ),
  );
  return (root: root, merger: merger, rescored: rescored);
}

/// `GET /admin/fixtures/{id}/copies` and `POST /admin/fixtures/{id}/merge`
/// (script 95, migration 0176).
void main() {
  group('copies', () {
    test('an admin reads the fixture first, then its copies', () async {
      final built = _root();
      final response = await copies_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.ok);
      final rows = (await decodeBody(response))['copies']! as List<Object?>;
      final first = rows.first! as Map<String, Object?>;
      final second = rows.last! as Map<String, Object?>;
      expect(first['fixture_id'], _copy);
      expect(first['is_self'], isTrue);
      expect(first['predictions'], 3);
      expect(second['fixture_id'], _kept);
      expect(second['hidden'], isFalse);
      expect(second['has_result'], isTrue);
      expect(second['kickoff_at'], '2026-10-15T19:00:00.000Z');
    });

    test('a player is refused', () async {
      final response = await copies_route.onRequest(
        wireContext(
          root: _root().root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('only GET', () async {
      final response = await copies_route.onRequest(
        wireContext(root: _root().root, principal: adminPrincipal()),
        _copy,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('merge', () {
    test('a preview answers the counts, nothing scored', () async {
      final built = _root();
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          body: const {'into': _kept, 'apply': false},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['moved'], 3);
      expect(body['doubles_dropped'], 1);
      expect(body['applied'], isFalse);
      expect(built.merger.applies, [false]);
      expect(built.rescored, isEmpty);
    });

    test('a merge scores the kept copy again', () async {
      final built = _root();
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          body: const {'into': _kept, 'apply': true},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['applied'], isTrue);
      expect(body['rescored'], isTrue);
      expect(body['link_moved'], isTrue);
      expect(built.rescored, [_kept]);
    });

    test('a merge the database refuses is 409 in Arabic', () async {
      final built = _root(
        refusal: const AppError.invariant(
          'competition.fixture_merge_refused',
          'دُمجت هذه النسخة من قبل.',
        ),
      );
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          body: const {'into': _kept, 'apply': true},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect(
        (await decodeBody(response))['message'],
        'دُمجت هذه النسخة من قبل.',
      );
      expect(built.rescored, isEmpty);
    });

    test('without apply it is 400, nothing merged', () async {
      final built = _root();
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          body: const {'into': _kept},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(built.merger.applies, isEmpty);
    });

    test('without a copy to keep it is 400 in Arabic', () async {
      final built = _root();
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: adminPrincipal(),
          body: const {'apply': true},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['message'], 'اختر النسخة التي تبقى.');
      expect(built.merger.applies, isEmpty);
    });

    test('a player is refused, nothing merged', () async {
      final built = _root();
      final response = await merge_route.onRequest(
        wireContext(
          root: built.root,
          principal: userPrincipal(),
          body: const {'into': _kept, 'apply': true},
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(built.merger.applies, isEmpty);
    });

    test('only POST', () async {
      final response = await merge_route.onRequest(
        wireContext(
          root: _root().root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _copy,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
