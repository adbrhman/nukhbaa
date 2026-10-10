/// `AdminApi`'s head-to-head desk (batch 93): each method reaches its route
/// with its method, path, query and body, and reads the answer.
library;

import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AdminApi head-to-head desk', () {
    test('h2hGroups: GET /admin/h2h/groups?day=', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'month_start': '2026-11-01',
          'drawn': true,
          'groups': [
            {
              'league_id': 'g-1',
              'division': 2,
              'free_slots': [3],
            },
          ],
        }),
      );

      final result = await AdminApi(ctx.transport).h2hGroups(day: '2026-11-05');

      final groups = (result as Ok<H2hAdminGroupsDto>).value;
      expect(groups.groups.single.freeSlots, [3]);
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/admin/h2h/groups');
      expect(req.url.queryParameters, {'day': '2026-11-05'});
    });

    test('h2hGroupRound: GET /admin/h2h/groups/{id}/rounds/{n}', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'round': 2,
          'status': 'live',
          'matches': <Object?>[],
        }),
      );

      final result = await AdminApi(
        ctx.transport,
      ).h2hGroupRound(leagueId: 'g-1', round: 2);

      expect((result as Ok<H2hGroupRoundDto>).value.status, 'live');
      final req = ctx.captured.single;
      expect(req.url.path, '/admin/h2h/groups/g-1/rounds/2');
      expect(req.url.queryParameters, isEmpty);
    });

    test('h2hPlayer: GET /admin/h2h/players/{id}', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'state': 'not_in_draw',
          'month_start': '2026-11-01',
        }),
      );

      final result = await AdminApi(ctx.transport).h2hPlayer('u-9');

      expect((result as Ok<MyH2hLeagueDto>).value.state, 'not_in_draw');
      expect(ctx.captured.single.url.path, '/admin/h2h/players/u-9');
    });

    test('h2hControls: GET /admin/h2h/controls', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'month_start': '2026-11-01',
          'settings': {'auto_approve': false, 'lead_hours': 6},
          'days': [
            {'day': '2026-11-14', 'fixture_count': 6, 'excluded': true},
          ],
          'actions': <Object?>[],
        }),
      );

      final result = await AdminApi(ctx.transport).h2hControls();

      final controls = (result as Ok<H2hControlsDto>).value;
      expect(controls.settings.autoApprove, isFalse);
      expect(controls.settings.leadHours, 6);
      expect(controls.days.single.excluded, isTrue);
      expect(ctx.captured.single.url.path, '/admin/h2h/controls');
    });

    test('saveH2hSettings: PUT the three choices', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{
          'auto_approve': true,
          'lead_hours': 12,
          'min_active_days': 4,
        }),
      );

      final result = await AdminApi(ctx.transport).saveH2hSettings(
        const H2hSettingsRequestDto(
          autoApprove: true,
          leadHours: 12,
          minActiveDays: 4,
        ),
      );

      expect((result as Ok<H2hSettingsDto>).value.minActiveDays, 4);
      final req = ctx.captured.single;
      expect(req.method, 'PUT');
      expect(req.url.path, '/admin/h2h/settings');
      expect(jsonDecode(req.body), {
        'auto_approve': true,
        'lead_hours': 12,
        'min_active_days': 4,
      });
    });

    test('a refused setting arrives with its h2h code', () async {
      final ctx = buildTransport(
        (_) async =>
            errorEnvelope(400, 'h2h.settings_out_of_range', 'out of range'),
      );

      final result = await AdminApi(ctx.transport).saveH2hSettings(
        const H2hSettingsRequestDto(
          autoApprove: true,
          leadHours: 48,
          minActiveDays: 4,
        ),
      );

      expect(
        (result as Err<H2hSettingsDto>).error.code,
        'h2h.settings_out_of_range',
      );
    });

    test('setH2hDayExcluded: POST {"day", "excluded"} -> changed', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{'changed': true}),
      );

      final result = await AdminApi(
        ctx.transport,
      ).setH2hDayExcluded(day: '2026-11-14', excluded: true);

      expect((result as Ok<bool>).value, isTrue);
      final req = ctx.captured.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/admin/h2h/exclusions');
      expect(jsonDecode(req.body), {'day': '2026-11-14', 'excluded': true});
    });

    test('addH2hSeat: POST the group, the player and the seat', () async {
      final ctx = buildTransport(
        (_) async => okJson(const <String, Object?>{'seated': true}),
      );

      final result = await AdminApi(ctx.transport).addH2hSeat(
        const H2hSeatRequestDto(leagueId: 'g-1', userId: 'u-9', slot: 3),
      );

      expect((result as Ok<bool>).value, isTrue);
      final req = ctx.captured.single;
      expect(req.url.path, '/admin/h2h/seats');
      expect(jsonDecode(req.body), {
        'league_id': 'g-1',
        'user_id': 'u-9',
        'slot': 3,
      });
    });

    test('h2hReport and runH2hJobs', () async {
      final ctx = buildTransport(
        (request) async => request.url.path == '/admin/h2h/report'
            ? okJson(const <String, Object?>{
                'month_start': '2026-11-01',
                'drawn': true,
                'seats': 65,
                'groups_by_division': {'1': 1, '4': 2},
              })
            : okJson(const <String, Object?>{
                'approved': 1,
                'locked': 2,
                'closed_months': 0,
                'drawn_seats': 0,
              }),
      );
      final api = AdminApi(ctx.transport);

      final report = await api.h2hReport(day: '2026-12-01');
      final run = await api.runH2hJobs();

      final reportDto = (report as Ok<H2hMonthReportDto>).value;
      expect(reportDto.seats, 65);
      expect(reportDto.groupsByDivision, {'1': 1, '4': 2});
      expect((run as Ok<H2hJobsRunDto>).value.locked, 2);
      expect(ctx.captured.first.url.queryParameters, {'day': '2026-12-01'});
      expect(ctx.captured.last.method, 'POST');
      expect(ctx.captured.last.url.path, '/admin/h2h/jobs');
    });
  });
}
