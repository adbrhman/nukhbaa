import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/users/[id]/points/index.dart' as route;
import 'competition_route_harness.dart';

final class _Reader implements PlayerPointsReader {
  final List<(String, String)> asked = <(String, String)>[];

  @override
  Future<Result<PlayerMonthPoints>> pointsOf({
    required UserId user,
    required SeasonId season,
  }) async {
    asked.add((user.value, season.value));
    return Result.ok(
      PlayerMonthPoints(
        participantId: kParticipantId,
        entries: <PlayerPointEntry>[
          PlayerPointEntry(
            id: 'e1',
            fixtureId: kFixtureId,
            homeTeam: 'Arsenal',
            awayTeam: 'Chelsea',
            kind: 'fixture_score',
            amount: 3,
            occurredAt: DateTime.utc(2026, 10, 10, 21),
          ),
          PlayerPointEntry(
            id: 'e2',
            fixtureId: kFixtureId,
            homeTeam: 'Arsenal',
            awayTeam: 'Chelsea',
            kind: 'streak_bonus',
            amount: 2,
            occurredAt: DateTime.utc(2026, 10, 10, 21, 1),
          ),
        ],
      ),
    );
  }
}

({CompositionRoot root, InMemoryAuditLogRepository audit}) _root(
  _Reader reader,
) {
  final InMemoryAuditLogRepository audit = InMemoryAuditLogRepository();
  return (
    root: CompositionRoot.forTesting(
      adminViewPlayerPoints: AdminViewPlayerPoints(
        reader: reader,
        auditRecorder: AuditRecorder(
          auditLog: audit,
          idGenerator: ScriptedIdGenerator([kAuditEntryId]),
          clock: FixedClock(DateTime.utc(2026, 10, 16)),
        ),
      ),
    ),
    audit: audit,
  );
}

/// `GET /admin/users/{id}/points?season=` (batch 146b, audit C-01).
void main() {
  test('an admin reads the player\'s month, with the matches named', () async {
    final _Reader reader = _Reader();
    final setup = _root(reader);

    final response = await route.onRequest(
      wireContext(
        root: setup.root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'season': kSeasonId},
      ),
      kUserId,
    );

    expect(response.statusCode, HttpStatus.ok);
    final Map<String, Object?> body = await decodeBody(response);
    expect(body['played'], isTrue);
    expect(body['month_points'], 3);
    expect(body['streak_bonus'], 2);
    final List<Object?> entries = body['entries']! as List<Object?>;
    expect((entries.first! as Map<String, Object?>)['home_team'], 'Arsenal');
    expect(
      (entries.first! as Map<String, Object?>)['occurred_at'],
      '2026-10-10T21:00:00.000Z',
    );
    expect(reader.asked, [(kUserId, kSeasonId)]);
  });

  test('a player is refused, nothing read', () async {
    final _Reader reader = _Reader();
    final response = await route.onRequest(
      wireContext(
        root: _root(reader).root,
        principal: userPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'season': kSeasonId},
      ),
      kUserId,
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(reader.asked, isEmpty);
  });

  test('no month named is 400', () async {
    final _Reader reader = _Reader();
    final response = await route.onRequest(
      wireContext(
        root: _root(reader).root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      kUserId,
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(reader.asked, isEmpty);
  });
}
