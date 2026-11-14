import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

MyH2hLeagueDto _dto({int groupStart = 1, int? waitingFor}) => MyH2hLeagueDto(
  state: 'open',
  monthStart: '2026-12-01',
  startsOn: '2026-11-01',
  isPilot: false,
  division: 2,
  groupIndex: 2,
  myRank: 1,
  promotionZone: 0,
  relegationZone: 0,
  groupStart: groupStart,
  waitingFor: waitingFor,
  standings: const <H2hStandingDto>[],
  rounds: const <H2hRoundViewDto>[],
);

void main() {
  group('MyH2hLeagueDto, NK277 waiting group', () {
    test('a waiting group survives the wire', () {
      final back = MyH2hLeagueDto.fromJson(
        _wire(_dto(groupStart: 20, waitingFor: 13).toJson()),
      );
      expect(back.groupStart, 20);
      expect(back.waitingFor, 13);
    });

    test('a group that plays sends no count', () {
      final json = _wire(_dto(groupStart: 8).toJson());
      expect(json['group_start'], 8);
      expect(json['waiting_for'], isNull);
      expect(MyH2hLeagueDto.fromJson(json).waitingFor, isNull);
    });

    test('a payload from a server before script 277 reads as a group drawn '
        'at the start', () {
      final json = _wire(_dto().toJson())
        ..remove('group_start')
        ..remove('waiting_for');
      final back = MyH2hLeagueDto.fromJson(json);
      expect(back.groupStart, 1);
      expect(back.waitingFor, isNull);
    });
  });
}
