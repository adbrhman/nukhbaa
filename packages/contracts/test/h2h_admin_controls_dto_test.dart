/// The wire shapes of the admin's head-to-head controls (batch 92) survive
/// a real JSON round trip, and tolerate an older or partial payload.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  test('H2hControlsDto survives the wire unchanged', () {
    const dto = H2hControlsDto(
      monthStart: '2026-11-01',
      settings: H2hSettingsDto(
        autoApprove: false,
        leadHours: 6,
        minActiveDays: 3,
        updatedByName: 'المشرف',
        updatedAt: '2026-11-09T20:00:00.000Z',
      ),
      days: [
        H2hControlDayDto(
          day: '2026-11-12',
          fixtureCount: 7,
          excluded: false,
          firstKickoff: '2026-11-12T12:00:00.000Z',
          round: 2,
        ),
        H2hControlDayDto(day: '2026-11-14', fixtureCount: 0, excluded: true),
      ],
      actions: [
        H2hAdminActionDto(
          id: 'line-1',
          action: 'seat_added',
          detail: {'slot': 3, 'user_id': 'u-4'},
          actedAt: '2026-11-09T20:00:00.000Z',
          actorId: 'a-1',
          actorName: 'المشرف',
        ),
      ],
    );

    final back = H2hControlsDto.fromJson(_wire(dto.toJson()));

    expect(back.toJson(), dto.toJson());
    expect(back.settings.leadHoursMax, 24);
    expect(back.days.last.round, isNull);
    expect(back.actions.single.detail['slot'], 3);
  });

  test('an empty controls payload reads as the defaults', () {
    final dto = H2hControlsDto.fromJson(const <String, Object?>{});

    expect(dto.schemaVersion, 1);
    expect(dto.settings.autoApprove, isTrue);
    expect(dto.settings.leadHours, 24);
    expect(dto.settings.minActiveDays, 5);
    expect(dto.days, isEmpty);
    expect(dto.actions, isEmpty);
  });

  test('H2hMonthReportDto survives the wire unchanged', () {
    const dto = H2hMonthReportDto(
      monthStart: '2026-11-01',
      drawn: true,
      isPilot: false,
      drawnSeats: 64,
      seats: 65,
      groupsByDivision: {'1': 1, '2': 1, '3': 1, '4': 2},
      closed: true,
      closedMembers: 65,
      outcomes: {'promoted': 9, 'held': 40, 'relegated': 9, 'out': 7},
      drawnAt: '2026-10-31T21:05:00.000Z',
      closedAt: '2026-12-01T00:10:00.000Z',
    );

    final back = H2hMonthReportDto.fromJson(_wire(dto.toJson()));

    expect(back.toJson(), dto.toJson());
    expect(back.groupsByDivision['4'], 2);
    expect(back.outcomes['out'], 7);
  });

  test('H2hJobsRunDto survives the wire unchanged', () {
    const dto = H2hJobsRunDto(
      approved: 1,
      locked: 2,
      closedMonths: 0,
      drawnSeats: 0,
    );

    expect(H2hJobsRunDto.fromJson(_wire(dto.toJson())).toJson(), dto.toJson());
  });

  test('the requests carry exactly what the admin chose', () {
    expect(
      const H2hSettingsRequestDto(
        autoApprove: true,
        leadHours: 12,
        minActiveDays: 4,
      ).toJson(),
      {'auto_approve': true, 'lead_hours': 12, 'min_active_days': 4},
    );
    expect(
      const H2hDayExclusionRequestDto(
        day: '2026-11-12',
        excluded: true,
      ).toJson(),
      {'day': '2026-11-12', 'excluded': true},
    );
    expect(
      const H2hSeatRequestDto(leagueId: 'l-1', userId: 'u-4', slot: 3).toJson(),
      {'league_id': 'l-1', 'user_id': 'u-4', 'slot': 3},
    );
    expect(
      const H2hSeatRequestDto(
        leagueId: 'l-1',
        userId: 'u-4',
        slot: 3,
        day: '2026-12-01',
      ).toJson()['day'],
      '2026-12-01',
    );
  });

  test('the admin group carries its free seats, empty from older servers', () {
    const group = H2hAdminGroupDto(
      leagueId: 'l-1',
      division: 4,
      groupIndex: 1,
      capacity: 20,
      promotionZone: 3,
      relegationZone: 0,
      standings: [],
      freeSlots: [17, 18, 19],
    );

    expect(H2hAdminGroupDto.fromJson(_wire(group.toJson())).freeSlots, [
      17,
      18,
      19,
    ]);
    expect(
      H2hAdminGroupDto.fromJson(const {'league_id': 'l-1'}).freeSlots,
      isEmpty,
    );
  });
}
