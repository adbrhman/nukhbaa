/// An admin or group command whose answer lands after its controller has
/// closed must end quietly.
///
/// Every one of these controllers is auto-disposed and wrote its answer
/// with no check, the shape behind FF7T in the error log ("Cannot use the
/// Ref of ... after it has been disposed"). The admin who leaves a section
/// while a request is out closes its controller. Each kind is driven once
/// here, with no listener and a server slower than one turn of the event
/// loop, so the controller is closed when the answer arrives.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/groups/groups_providers.dart';

import '../../support/admin_harness.dart';

AdminHarness _slowServer() {
  final harness = buildAdminHarness((http.Request request) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return errorEnvelope(503, 'server.unavailable', 'down');
  });
  addTearDown(harness.dispose);
  return harness;
}

void main() {
  test('a user search', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(usersLookupControllerProvider.notifier)
          .search('nukhba'),
      completes,
    );
    expect(harness.captured, hasLength(1));
  });

  test('a suspension', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(userSanctionControllerProvider.notifier)
          .suspend('user-9', 'reason'),
      completes,
    );
    expect(harness.captured, hasLength(1));
  });

  test('hiding fixtures (a hand-written controller)', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(fixtureVisibilityControllerProvider.notifier)
          .setHidden(
            seasonId: 's-1',
            fixtureIds: <String>['f-1'],
            hidden: true,
          ),
      completes,
    );
    expect(harness.captured, hasLength(1));
  });

  test('a result recorded', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(recordFixtureResultControllerProvider.notifier)
          .record(
            fixtureId: 'f-1',
            seasonId: 's-1',
            homeGoals: 2,
            awayGoals: 1,
          ),
      completes,
    );
    expect(harness.captured, hasLength(1));
  });

  test('a match added (its first request already fails)', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(addMatchControllerProvider.notifier)
          .submit(
            seasonId: 's-1',
            homeTeam: 'Al Hilal',
            awayTeam: 'Al Nassr',
            kickoffAt: '2026-12-01T18:00:00Z',
            displayOrder: 0,
          ),
      completes,
    );
    expect(harness.captured, hasLength(1));
  });

  test('a group created and a group joined', () async {
    final harness = _slowServer();
    await expectLater(
      harness.container
          .read(createGroupControllerProvider.notifier)
          .create('league'),
      completes,
    );
    await expectLater(
      harness.container
          .read(joinGroupControllerProvider.notifier)
          .join('ABC123'),
      completes,
    );
    expect(harness.captured, hasLength(2));
  });
}
