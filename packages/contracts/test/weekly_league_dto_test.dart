import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('MyWeeklyLeagueDto', () {
    const dto = MyWeeklyLeagueDto(
      weekStart: '2026-09-21',
      weekEnd: '2026-09-27',
      tier: 2,
      groupIndex: 1,
      myRank: 2,
      promotionZone: 2,
      relegationZone: 2,
      entries: [
        WeeklyLeagueEntryDto(
          rank: 1,
          userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          points: 30,
          exactCount: 3,
          decidedCount: 6,
          projectedOutcome: 'promoted',
          isMe: false,
        ),
        WeeklyLeagueEntryDto(
          rank: 2,
          userId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          points: 10,
          exactCount: 1,
          decidedCount: 3,
          projectedOutcome: 'held',
          isMe: true,
        ),
      ],
    );

    test('round-trips through JSON', () {
      expect(MyWeeklyLeagueDto.fromJson(dto.toJson()), dto);
    });

    test('writes snake_case keys and the current schema version', () {
      final json = dto.toJson();
      expect(json['schema_version'], MyWeeklyLeagueDto.currentSchemaVersion);
      expect(json['week_start'], '2026-09-21');
      expect(json['week_end'], '2026-09-27');
      expect(json['tier'], 2);
      expect(json['group_index'], 1);
      expect(json['my_rank'], 2);
      expect(json['promotion_zone'], 2);
      expect(json['relegation_zone'], 2);
      final entries = (json['entries']! as List).cast<Map<String, Object?>>();
      expect(entries.last['user_id'], 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      expect(entries.last['projected_outcome'], 'held');
      expect(entries.last['is_me'], true);
    });

    test('a payload with no entries and no keys still parses', () {
      final parsed = MyWeeklyLeagueDto.fromJson(const {'schema_version': 1});
      expect(parsed.entries, isEmpty);
      expect(parsed.myRank, 0);
      expect(parsed.tier, 1);
    });

    test('a different rank is a different reading', () {
      final other = MyWeeklyLeagueDto.fromJson({...dto.toJson(), 'my_rank': 1});
      expect(other, isNot(dto));
    });
  });
}
