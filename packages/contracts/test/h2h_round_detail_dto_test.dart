import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  group('MyH2hRoundDto', () {
    const dto = MyH2hRoundDto(
      round: 2,
      day: '2026-10-11',
      status: 'live',
      fixtureCount: 3,
      firstKickoff: '2026-10-11T10:30:00.000Z',
      opponentUserId: 'u-2',
      opponentName: 'مالك سنان',
      myPoints: 7,
      opponentPoints: 4,
      result: 'win',
      mine: H2hSideTotalsDto(predicted: 3, exact: 1, doubles: 1),
      theirs: H2hSideTotalsDto(predicted: 2, exact: 0, doubles: 0),
      fixtures: [
        H2hRoundFixtureDto(
          fixtureId: 'f-1',
          homeTeam: 'Bayern',
          awayTeam: 'Dortmund',
          kickoffAt: '2026-10-11T10:30:00.000Z',
          state: 'finished',
          homeGoals: 2,
          awayGoals: 1,
          mine: H2hPickDto(
            homeGoals: 2,
            awayGoals: 1,
            isDouble: true,
            points: 6,
            exact: true,
          ),
          theirs: H2hPickDto(homeGoals: 1, awayGoals: 1, isDouble: false),
          theirsHidden: false,
        ),
        H2hRoundFixtureDto(
          fixtureId: 'f-2',
          homeTeam: 'Real Madrid',
          awayTeam: 'Villarreal',
          kickoffAt: '2026-10-11T19:00:00.000Z',
          state: 'not_started',
          mine: H2hPickDto(homeGoals: 3, awayGoals: 0, isDouble: false),
          theirsHidden: true,
        ),
      ],
    );

    test('survives a JSON round trip unchanged', () {
      final json = _wire(dto.toJson());
      expect(MyH2hRoundDto.fromJson(json).toJson(), dto.toJson());
    });

    test('a hidden pick is null on the wire, and says it is hidden', () {
      final fixtures = (dto.toJson()['fixtures']! as List)
          .cast<Map<String, Object?>>();
      expect(fixtures.last['theirs'], isNull);
      expect(fixtures.last['theirs_hidden'], true);
      expect(fixtures.first['theirs'], isNotNull);
      expect(fixtures.first['theirs_hidden'], false);
    });

    test('the group average has no opponent counts', () {
      final parsed = MyH2hRoundDto.fromJson(const {
        'round': 1,
        'mine': {'predicted': 2, 'exact': 0, 'doubles': 0},
        'opponent_points': 3,
      });
      expect(parsed.theirs, isNull);
      expect(parsed.opponentUserId, isNull);
      expect(parsed.opponentPoints, 3.0);
      expect(parsed.mine.predicted, 2);
      expect(parsed.fixtures, isEmpty);
    });
  });

  group('the league reading, version 1 still', () {
    test('a round view carries its first kickoff; old payloads parse', () {
      const view = H2hRoundViewDto(
        round: 1,
        day: '2026-10-10',
        status: 'open',
        fixtureCount: 22,
        firstKickoff: '2026-10-10T11:30:00.000Z',
      );
      final json = _wire(view.toJson());
      expect(json['first_kickoff'], '2026-10-10T11:30:00.000Z');
      expect(H2hRoundViewDto.fromJson(json).firstKickoff, view.firstKickoff);
      expect(H2hRoundViewDto.fromJson(const {'round': 1}).firstKickoff, isNull);
    });

    test('the month carries the days left; old payloads read 0', () {
      final json = _wire(
        const MyH2hLeagueDto(
          state: 'open',
          monthStart: '2026-10-01',
          startsOn: '2026-11-01',
          isPilot: true,
          myRank: 0,
          promotionZone: 0,
          relegationZone: 3,
          standings: [],
          rounds: [],
          daysLeft: 21,
        ).toJson(),
      );
      expect(json['days_left'], 21);
      expect(MyH2hLeagueDto.fromJson(json).daysLeft, 21);
      expect(MyH2hLeagueDto.fromJson(const {'state': 'open'}).daysLeft, 0);
    });
  });
}
