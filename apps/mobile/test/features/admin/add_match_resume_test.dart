/// Adding a match is two requests, register then link to the month (audit
/// L-12). When the link fails, the registered match is kept: sending the
/// same match again links it, and never registers a second copy -- which
/// migration 0110 would refuse anyway, leaving an orphan no month shows.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/widgets/riyadh_kickoff_field.dart';

import '../../support/admin_harness.dart';

const Map<String, Object?> _registered = <String, Object?>{
  'schema_version': 1,
  'fixture_id': 'f-1',
  'home_team': 'Al Hilal',
  'away_team': 'Al Nassr',
  'kickoff_at': '2026-12-01T18:00:00.000Z',
};

void main() {
  test('a failed link is resumed with the same match, not registered '
      'twice', () async {
    var links = 0;
    final AdminHarness harness = buildAdminHarness((
      http.Request request,
    ) async {
      switch (request.url.path) {
        case '/fixtures':
          return okJsonObject(_registered);
        case '/seasons/s-1/fixtures':
          links++;
          if (links == 1) {
            return errorEnvelope(
              409,
              'competition.display_order_taken',
              'taken',
            );
          }
          return okJsonObject(<String, Object?>{
            'schema_version': 1,
            'season_id': 's-1',
            'fixture_id': 'f-1',
            'display_order': 0,
          });
      }
      return errorEnvelope(404, 'test.unrouted', request.url.path);
    });
    addTearDown(harness.dispose);
    final sub = harness.container.listen(addMatchControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final AddMatchController notifier = harness.container.read(
      addMatchControllerProvider.notifier,
    );

    Future<void> submit() => notifier.submit(
      seasonId: 's-1',
      homeTeam: 'Al Hilal',
      awayTeam: 'Al Nassr',
      // The same instant as the server's answer, written differently.
      kickoffAt: '2026-12-01T18:00:00Z',
      displayOrder: 0,
    );

    await submit();
    expect(
      harness.container.read(addMatchControllerProvider),
      isA<AsyncError<AddMatchResult>>(),
    );
    expect(notifier.unlinked?.fixtureId, 'f-1');

    await submit();
    expect(
      harness.container.read(addMatchControllerProvider),
      isA<AsyncData<AddMatchResult>>(),
    );
    expect(notifier.unlinked, isNull);
    expect(
      <String>[for (final c in harness.captured) c.request.url.path],
      <String>['/fixtures', '/seasons/s-1/fixtures', '/seasons/s-1/fixtures'],
    );
    expect(
      jsonDecode(harness.captured.last.request.body),
      containsPair('fixture_id', 'f-1'),
    );
  });

  test('another match after a failed link is registered as its own', () async {
    final AdminHarness harness = buildAdminHarness((
      http.Request request,
    ) async {
      if (request.url.path == '/fixtures') return okJsonObject(_registered);
      return errorEnvelope(409, 'competition.display_order_taken', 'taken');
    });
    addTearDown(harness.dispose);
    final sub = harness.container.listen(addMatchControllerProvider, (_, _) {});
    addTearDown(sub.close);
    final AddMatchController notifier = harness.container.read(
      addMatchControllerProvider.notifier,
    );

    await notifier.submit(
      seasonId: 's-1',
      homeTeam: 'Al Hilal',
      awayTeam: 'Al Nassr',
      kickoffAt: '2026-12-01T18:00:00Z',
      displayOrder: 0,
    );
    await notifier.submit(
      seasonId: 's-1',
      homeTeam: 'Al Ahli',
      awayTeam: 'Al Nassr',
      kickoffAt: '2026-12-02T18:00:00Z',
      displayOrder: 0,
    );

    expect(
      harness.captured.where((c) => c.request.url.path == '/fixtures'),
      hasLength(2),
    );
  });

  test('the form says the kickoff is on Riyadh\'s clock', () {
    expect(RiyadhKickoffField.zoneLine(null), 'أدخل الموعد بتوقيت الرياض');
    expect(
      RiyadhKickoffField.zoneLine(DateTime.utc(2026, 10, 20, 18)),
      startsWith('بتوقيت الرياض'),
    );
  });
}
