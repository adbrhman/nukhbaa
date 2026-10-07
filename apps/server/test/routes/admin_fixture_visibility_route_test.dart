import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/fixture-visibility/index.dart' as visibility_route;
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/index.dart' as browse_route;
import 'competition_route_harness.dart';

const _hiddenFixture = '61616161-6161-6161-6161-616161616161';
const _testFixture = '62626262-6262-6262-6262-626262626262';

/// The visibility column over the harness's schedules: hiding rewrites the
/// stored schedule with a `hiddenAt`, exactly what the Postgres store does
/// to the row.
final class _Store implements FixtureVisibilityStore {
  _Store(this.schedules);

  final Map<String, FixtureSchedule> schedules;

  @override
  Future<Result<List<FixtureRef>>> setHidden(
    List<FixtureRef> fixtures, {
    required bool hidden,
  }) async {
    final changed = <FixtureRef>[];
    for (final fixture in fixtures) {
      final current = schedules[fixture.value];
      if (current == null || current.isHidden == hidden) continue;
      schedules[fixture.value] = FixtureSchedule.fromStored(
        fixture: current.fixture,
        homeTeam: current.homeTeam,
        awayTeam: current.awayTeam,
        kickoffAt: current.kickoffAt,
        isTest: current.isTest,
        hiddenAt: hidden ? DateTime.utc(2026, 10, 7, 12) : null,
      );
      changed.add(fixture);
    }
    return Result.ok(changed);
  }
}

/// Answers the schedules [_Store] keeps, so a hide is visible to the next
/// browse exactly as it is on the server.
final class _Schedules implements FixtureScheduleRepository {
  _Schedules(this.schedules);

  final Map<String, FixtureSchedule> schedules;

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    schedules[schedule.fixture.value] = schedule;
    return const Result.ok(null);
  }

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async =>
      Result.ok(schedules[fixture.value]);

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async => Result.ok([
    for (final f in fixtures)
      if (schedules[f.value] != null) schedules[f.value]!,
  ]);
}

final class _Predictions extends Mock implements FixturePredictionRepository {}

FixtureSchedule _schedule(String id, {bool isTest = false}) =>
    FixtureSchedule.fromStored(
      fixture: FixtureRef(id),
      homeTeam: 'Home $id',
      awayTeam: 'Away $id',
      kickoffAt: DateTime.utc(2026, 10, 20, 18),
      isTest: isTest,
    );

void main() {
  setUpAll(() => registerFallbackValue(const SeasonId(kSeasonId)));

  late Map<String, FixtureSchedule> schedules;
  late InMemoryAuditLogRepository audit;
  late CompositionRoot root;

  setUp(() {
    schedules = {
      kFixtureId: _schedule(kFixtureId),
      _hiddenFixture: _schedule(_hiddenFixture),
      _testFixture: _schedule(_testFixture, isTest: true),
    };
    audit = InMemoryAuditLogRepository();
    final predictions = _Predictions();
    when(() => predictions.listSeasonFixtures(any())).thenAnswer(
      (_) async => const Result.ok([
        FixtureRef(kFixtureId),
        FixtureRef(_hiddenFixture),
        FixtureRef(_testFixture),
      ]),
    );
    root = CompositionRoot.forTesting(
      adminSetFixturesHidden: AdminSetFixturesHidden(
        store: _Store(schedules),
        auditRecorder: AuditRecorder(
          auditLog: audit,
          idGenerator: ScriptedIdGenerator([kAuditEntryId, kAuditEntryId2]),
          clock: FixedClock(DateTime.utc(2026, 10, 7, 12)),
        ),
      ),
      browseSeasonFixtures: BrowseSeasonFixtures(
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: _Schedules(schedules),
      ),
    );
  });

  Future<Response> setHidden(AuthenticatedUser principal, Object? body) =>
      visibility_route.onRequest(
        wireContext(root: root, principal: principal, body: body),
      );

  Future<List<Map<String, Object?>>> browse(
    AuthenticatedUser principal, {
    bool includeHidden = false,
  }) async {
    final response = await browse_route.onRequest(
      wireContext(
        root: root,
        principal: principal,
        method: HttpMethod.get,
        queryParameters: includeHidden
            ? const {'include_hidden': 'true'}
            : const {},
      ),
      kSeasonId,
    );
    expect(response.statusCode, HttpStatus.ok);
    final List<Object?> list = await response.json() as List<Object?>;
    return [for (final Object? e in list) e! as Map<String, Object?>];
  }

  List<String> ids(List<Map<String, Object?>> cards) => [
    for (final card in cards) card['fixture_id']! as String,
  ];

  group('POST /admin/fixture-visibility', () {
    test('an admin hides a fixture: players stop seeing it, and it is '
        'audited', () async {
      final response = await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture],
        'hidden': true,
      });

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['changed'], [_hiddenFixture]);
      expect(body['hidden'], true);
      expect(audit.entries.single.action, AuditAction.fixtureHidden);
      expect(audit.entries.single.targetRef, _hiddenFixture);

      expect(ids(await browse(userPrincipal())), [kFixtureId]);
    });

    test('several fixtures in one call; one already hidden is not '
        'changed twice', () async {
      await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture],
        'hidden': true,
      });

      final response = await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture, kFixtureId],
        'hidden': true,
      });

      expect((await decodeBody(response))['changed'], [kFixtureId]);
      expect(audit.entries, hasLength(2));
    });

    test('showing it again brings it back, with nothing lost', () async {
      await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture],
        'hidden': true,
      });
      final response = await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture],
        'hidden': false,
      });

      expect((await decodeBody(response))['changed'], [_hiddenFixture]);
      expect(audit.entries.last.action, AuditAction.fixtureShown);
      expect(ids(await browse(userPrincipal())), [kFixtureId, _hiddenFixture]);
    });

    test('a player is refused, and nothing changes', () async {
      final response = await setHidden(userPrincipal(), {
        'fixture_ids': [kFixtureId],
        'hidden': true,
      });

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(schedules[kFixtureId]!.isHidden, isFalse);
      expect(audit.entries, isEmpty);
    });

    test('a malformed body is 400', () async {
      final missingFlag = await setHidden(adminPrincipal(), {
        'fixture_ids': [kFixtureId],
      });
      expect(missingFlag.statusCode, HttpStatus.badRequest);

      final notAList = await setHidden(adminPrincipal(), {
        'fixture_ids': kFixtureId,
        'hidden': true,
      });
      expect(notAList.statusCode, HttpStatus.badRequest);

      final empty = await setHidden(adminPrincipal(), {
        'fixture_ids': <String>[],
        'hidden': true,
      });
      expect(empty.statusCode, HttpStatus.badRequest);
      expect(audit.entries, isEmpty);
    });
  });

  group('GET /seasons/{id}/fixtures and hidden/test fixtures', () {
    setUp(() async {
      await setHidden(adminPrincipal(), {
        'fixture_ids': [_hiddenFixture],
        'hidden': true,
      });
    });

    test('a player gets neither the hidden nor the test fixture, even when '
        'asking for hidden ones', () async {
      expect(ids(await browse(userPrincipal())), [kFixtureId]);
      expect(ids(await browse(userPrincipal(), includeHidden: true)), [
        kFixtureId,
      ]);
    });

    test('an admin gets the test fixture, flagged, but not the hidden one '
        'unless asking', () async {
      final cards = await browse(adminPrincipal());
      expect(ids(cards), [kFixtureId, _testFixture]);
      expect(cards.last['is_test'], true);
      expect(cards.first.containsKey('is_test'), isFalse);
    });

    test('the admin panel asks for everything, each one flagged', () async {
      final cards = await browse(adminPrincipal(), includeHidden: true);
      expect(ids(cards), [kFixtureId, _hiddenFixture, _testFixture]);
      expect(cards[1]['hidden'], true);
      expect(cards[2]['is_test'], true);
    });
  });
}
