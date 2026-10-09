import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  group('MyH2hLeagueDto', () {
    const dto = MyH2hLeagueDto(
      state: 'open',
      monthStart: '2026-11-01',
      startsOn: '2026-11-01',
      isPilot: false,
      division: 2,
      groupIndex: 0,
      myRank: 2,
      promotionZone: 3,
      relegationZone: 3,
      standings: [
        H2hStandingDto(
          rank: 1,
          userId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          displayName: 'Nora',
          played: 3,
          won: 2,
          drawn: 1,
          lost: 0,
          leaguePoints: 7,
          pointsFor: 31,
          exactCount: 2,
          form: ['win', 'draw', 'win'],
          isMe: false,
          avatarUrl: '/users/aaaaaaaa/avatar?v=1',
        ),
        H2hStandingDto(
          rank: 2,
          userId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          displayName: 'Sami',
          played: 3,
          won: 1,
          drawn: 1,
          lost: 1,
          leaguePoints: 4,
          pointsFor: 20,
          exactCount: 1,
          form: ['loss', 'draw', 'win'],
          isMe: true,
        ),
      ],
      rounds: [
        H2hRoundViewDto(
          round: 1,
          day: '2026-11-01',
          status: 'settled',
          fixtureCount: 8,
          opponentUserId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          opponentName: 'Nora',
          myPoints: 6,
          opponentPoints: 9,
          result: 'loss',
        ),
        H2hRoundViewDto(
          round: 2,
          day: '2026-11-04',
          status: 'live',
          fixtureCount: 6,
          myPoints: 4,
          opponentPoints: 3.5,
          result: 'win',
        ),
        H2hRoundViewDto(
          round: 3,
          day: '2026-11-07',
          status: 'upcoming',
          fixtureCount: 10,
        ),
      ],
    );

    test('survives a JSON round trip unchanged', () {
      final json = _wire(dto.toJson());
      expect(MyH2hLeagueDto.fromJson(json).toJson(), dto.toJson());
    });

    test('writes snake_case keys and the current schema version', () {
      final json = dto.toJson();
      expect(json['schema_version'], MyH2hLeagueDto.currentSchemaVersion);
      expect(json['state'], 'open');
      expect(json['month_start'], '2026-11-01');
      expect(json['starts_on'], '2026-11-01');
      expect(json['is_pilot'], false);
      expect(json['division'], 2);
      expect(json['group_index'], 0);
      expect(json['my_rank'], 2);
      expect(json['promotion_zone'], 3);
      expect(json['relegation_zone'], 3);
      final standings = (json['standings']! as List)
          .cast<Map<String, Object?>>();
      expect(standings.first['league_points'], 7);
      expect(standings.first['points_for'], 31);
      expect(standings.first['form'], ['win', 'draw', 'win']);
      expect(standings.last['is_me'], true);
      expect(standings.last['avatar_url'], isNull);
      final rounds = (json['rounds']! as List).cast<Map<String, Object?>>();
      expect(rounds.first['opponent_user_id'], isNotNull);
      expect(rounds[1]['opponent_user_id'], isNull);
      expect(rounds[1]['opponent_points'], 3.5);
      expect(rounds.last['my_points'], isNull);
      expect(rounds.last['result'], isNull);
    });

    test('a whole-number average read back as an int is still a double', () {
      final round = H2hRoundViewDto.fromJson(const {
        'round': 1,
        'day': '2026-11-01',
        'status': 'settled',
        'fixture_count': 6,
        'my_points': 4,
        'opponent_points': 4,
        'result': 'draw',
      });
      expect(round.opponentPoints, 4.0);
    });

    test('a payload with no keys still parses, as not started', () {
      final parsed = MyH2hLeagueDto.fromJson(const {'schema_version': 1});
      expect(parsed.state, 'not_started');
      expect(parsed.division, isNull);
      expect(parsed.standings, isEmpty);
      expect(parsed.rounds, isEmpty);
      expect(parsed.myRank, 0);
    });
  });

  group('H2hRoundsOverviewDto', () {
    const dto = H2hRoundsOverviewDto(
      monthStart: '2026-11-01',
      drawn: true,
      isPilot: false,
      rounds: [
        H2hRoundDto(
          id: '11111111-1111-1111-1111-111111111111',
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

    test('survives a JSON round trip unchanged', () {
      final json = _wire(dto.toJson());
      expect(H2hRoundsOverviewDto.fromJson(json).toJson(), dto.toJson());
    });

    test('writes snake_case keys', () {
      final json = dto.toJson();
      expect(json['month_start'], '2026-11-01');
      final round = (json['rounds']! as List).single as Map<String, Object?>;
      expect(round['fixture_count'], 8);
      expect(round['automatic'], true);
      final candidate =
          (json['candidates']! as List).single as Map<String, Object?>;
      expect(candidate['first_kickoff'], '2026-11-04T15:00:00.000Z');
      expect(candidate['kind'], 'fill');
    });
  });

  test('the approve request and the pilot answer round-trip', () {
    const request = H2hApproveRoundRequestDto(day: '2026-11-04');
    expect(
      H2hApproveRoundRequestDto.fromJson(_wire(request.toJson())).day,
      '2026-11-04',
    );
    expect(H2hApproveRoundRequestDto.fromJson(const {}).day, '');
    const started = H2hPilotStartedDto(seated: 24);
    expect(H2hPilotStartedDto.fromJson(_wire(started.toJson())).seated, 24);
  });
}
