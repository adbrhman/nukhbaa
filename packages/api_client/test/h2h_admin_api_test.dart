import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AdminApi head-to-head rounds', () {
    test('h2hRounds: GET /admin/h2h/rounds, the month by ?day=', () async {
      const expected = H2hRoundsOverviewDto(
        monthStart: '2026-11-01',
        startsOn: '2026-11-01',
        drawn: true,
        isPilot: false,
        rounds: [
          H2hRoundDto(
            id: 'r-1',
            round: 1,
            day: '2026-11-01',
            fixtureCount: 8,
            automatic: true,
            locked: true,
          ),
        ],
        candidates: [
          H2hCandidateDayDto(
            day: '2026-11-04',
            fixtureCount: 5,
            firstKickoff: '2026-11-04T15:00:00.000Z',
            kind: 'fill',
          ),
        ],
      );
      final ctx = buildTransport((_) async => okJson(expected.toJson()));

      final result = await AdminApi(ctx.transport).h2hRounds(day: '2026-11-05');

      expect(
        (result as Ok<H2hRoundsOverviewDto>).value.toJson(),
        expected.toJson(),
      );
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/admin/h2h/rounds');
      expect(req.url.queryParameters, {'day': '2026-11-05'});
    });

    test('h2hRounds without a day sends no query', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{'month_start': ''}),
      );

      await AdminApi(ctx.transport).h2hRounds();

      expect(ctx.captured.single.url.queryParameters, isEmpty);
    });

    test('approveH2hRound: POST {"day"} -> the new round', () async {
      final ctx = buildTransport(
        (_) async => okJson(
          const H2hRoundDto(
            id: 'r-4',
            round: 4,
            day: '2026-11-15',
            fixtureCount: 5,
            automatic: false,
            locked: false,
          ).toJson(),
        ),
      );

      final result = await AdminApi(
        ctx.transport,
      ).approveH2hRound('2026-11-15');

      final round = (result as Ok<H2hRoundDto>).value;
      expect(round.round, 4);
      expect(round.automatic, isFalse);
      final req = ctx.captured.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/admin/h2h/rounds');
      expect(jsonDecode(req.body), {'day': '2026-11-15'});
    });

    test('a refused approval arrives with its h2h code', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(
          409,
          'h2h.round_day_started',
          'A round must be approved before its first match kicks off',
        ),
      );

      final result = await AdminApi(
        ctx.transport,
      ).approveH2hRound('2026-11-01');

      expect((result as Err<H2hRoundDto>).error.code, 'h2h.round_day_started');
    });

    test('withdrawH2hRound: DELETE /admin/h2h/rounds/{id}', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{'withdrawn': true}),
      );

      final result = await AdminApi(ctx.transport).withdrawH2hRound('r-4');

      expect(result, const Result<bool>.ok(true));
      final req = ctx.captured.single;
      expect(req.method, 'DELETE');
      expect(req.url.path, '/admin/h2h/rounds/r-4');
    });

    test('startH2hPilot: POST /admin/h2h/pilot -> the seats', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{'seated': 24}),
      );

      final result = await AdminApi(ctx.transport).startH2hPilot();

      expect(result, const Result<int>.ok(24));
      final req = ctx.captured.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/admin/h2h/pilot');
    });
  });
}
