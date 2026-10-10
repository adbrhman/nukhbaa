/// The groups added to a drawn month (2026-10-11) survive a real JSON round
/// trip, and an empty payload reads without failing.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  test('the groups opened survive the wire', () {
    const added = H2hGroupsAddedDto(
      monthStart: '2026-10-01',
      groups: [
        H2hAddedGroupDto(
          leagueId: '22222222-2222-4222-8222-222222222222',
          division: 2,
          groupIndex: 0,
          seats: 20,
        ),
        H2hAddedGroupDto(
          leagueId: '44444444-4444-4444-8444-444444444444',
          division: 4,
          groupIndex: 0,
          seats: 20,
        ),
      ],
      seats: 40,
      waiting: 12,
    );

    final back = H2hGroupsAddedDto.fromJson(_wire(added.toJson()));

    expect(back.toJson(), added.toJson());
    expect(back.groups.last.division, 4);
    expect(back.waiting, 12);
  });

  test('an empty payload reads as nothing added', () {
    final added = H2hGroupsAddedDto.fromJson(const <String, Object?>{});

    expect(added.groups, isEmpty);
    expect(added.seats, 0);
  });

  test('the request carries the count only', () {
    expect(const H2hAddGroupsRequestDto(groups: 3).toJson(), {'groups': 3});
  });
}
