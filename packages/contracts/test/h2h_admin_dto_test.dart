import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  test('H2hAdminGroupsDto survives the wire unchanged', () {
    const dto = H2hAdminGroupsDto(
      monthStart: '2026-11-01',
      drawn: true,
      isPilot: false,
      seatedCount: 42,
      rounds: [
        H2hRoundDto(
          id: 'r-1',
          round: 1,
          day: '2026-11-03',
          fixtureCount: 7,
          automatic: true,
          locked: true,
        ),
      ],
      groups: [
        H2hAdminGroupDto(
          leagueId: 'l-1',
          division: 1,
          groupIndex: 0,
          capacity: 20,
          promotionZone: 0,
          relegationZone: 3,
          standings: [
            H2hStandingDto(
              rank: 1,
              userId: 'u-1',
              displayName: 'سامي',
              played: 1,
              won: 1,
              drawn: 0,
              lost: 0,
              leaguePoints: 3,
              pointsFor: 9,
              exactCount: 1,
              form: ['win'],
              isMe: false,
            ),
          ],
        ),
      ],
    );

    final back = H2hAdminGroupsDto.fromJson(_wire(dto.toJson()));

    expect(back.toJson(), dto.toJson());
    expect(back.groups.single.standings.single.displayName, 'سامي');
  });

  test('an undrawn month parses with no group', () {
    final back = H2hAdminGroupsDto.fromJson(
      _wire(<String, Object?>{'month_start': '2026-12-01'}),
    );

    expect(back.drawn, isFalse);
    expect(back.groups, isEmpty);
    expect(back.rounds, isEmpty);
  });
}
