/// The admin's desk for relegation for absence (NK183, migration 0189)
/// from the real handlers and the real `AdminH2hAbsence`: the view of a
/// month the rules do not run in, and every refusal the routes and the
/// use-case make before touching a store. The rules themselves are tested
/// in the application package (h2h_absence_test.dart) and the SQL in
/// supabase/tests/0189_h2h_seat_moves_test.sql.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/h2h/absence/index.dart' as absence_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/excusals/index.dart' as excusals_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/relegations/index.dart' as relegations_route;
import 'competition_route_harness.dart';

/// 2026-11-02 12:00 UTC: November, an elite month.
final _now = DateTime.utc(2026, 11, 2, 12);

/// November is not drawn: the rules do not run. Nothing else is read.
final class _Leagues implements H2hLeagueStore {
  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async =>
      const Result.ok(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not reached: ${invocation.memberName}');
}

/// Every other store: a test that reaches one fails.
final class _Unreached
    implements H2hRoundStore, H2hSheetReader, H2hSeatMoveStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not reached: ${invocation.memberName}');
}

final class _NoProfiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => const Result.ok({});
}

final class _Silent implements PushSender {
  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async => const Result.ok(<String>[]);
}

final class _Ids implements IdGenerator {
  @override
  String newUuid() => '00000000-0000-4000-8000-000000000001';
}

final class _At implements Clock {
  @override
  DateTime nowUtc() => _now;
}

CompositionRoot _root() {
  final unreached = _Unreached();
  return CompositionRoot.forTesting(
    h2hAbsenceDesk: AdminH2hAbsence(
      leagues: _Leagues(),
      rounds: unreached,
      sheets: unreached,
      moves: unreached,
      profiles: _NoProfiles(),
      sender: _Silent(),
      idGenerator: _Ids(),
      clock: _At(),
    ),
  );
}

void main() {
  group('GET /admin/h2h/absence', () {
    test('a month the rules do not run in is read as inactive', () async {
      final response = await absence_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['active'], false);
      expect(body['month_start'], '2026-11-01');
      expect(body['watch'], isEmpty);
      expect(body['moves'], isEmpty);
    });

    test('a player is refused', () async {
      final response = await absence_route.onRequest(
        wireContext(
          root: _root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('POST /admin/h2h/relegations', () {
    test('an id that is not a user id is 400', () async {
      final response = await relegations_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          body: const {'user_id': 'nobody', 'reason': 'تلاعب'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.user_invalid');
    });

    test('a blank reason is 400, before any store is read', () async {
      final response = await relegations_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          body: const {
            'user_id': '00000000-0000-4000-9000-000000000001',
            'reason': '   ',
          },
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.reason_required');
    });

    test('a month the rules do not run in is 409', () async {
      final response = await relegations_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          body: const {
            'user_id': '00000000-0000-4000-9000-000000000001',
            'reason': 'تلاعب',
          },
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.absence_inactive');
    });

    test('a player is refused', () async {
      final response = await relegations_route.onRequest(
        wireContext(
          root: _root(),
          principal: userPrincipal(),
          body: const {
            'user_id': '00000000-0000-4000-9000-000000000001',
            'reason': 'تلاعب',
          },
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('POST /admin/h2h/excusals', () {
    test('an id that is not a round id is 400', () async {
      final response = await excusals_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          body: const {'round_id': 7, 'reason': 'تعطل'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.round_invalid');
    });

    test('a missing reason is 400', () async {
      final response = await excusals_route.onRequest(
        wireContext(
          root: _root(),
          principal: adminPrincipal(),
          body: const {'round_id': '22222222-2222-4222-8222-000000000003'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.reason_required');
    });

    test('a player is refused', () async {
      final response = await excusals_route.onRequest(
        wireContext(
          root: _root(),
          principal: userPrincipal(),
          body: const {
            'round_id': '22222222-2222-4222-8222-000000000003',
            'reason': 'تعطل',
          },
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });
}
