// NK308_02
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

const H2hCupPlayerDto _alice = H2hCupPlayerDto(
  userId: 'u-1',
  displayName: 'Alice',
  groupNumber: 1,
  isMe: true,
);

const H2hCupPlayerDto _bob = H2hCupPlayerDto(
  userId: 'u-2',
  displayName: 'Bob',
  groupNumber: 2,
  isMe: false,
);

const H2hPickDto _pick = H2hPickDto(
  homeGoals: 2,
  awayGoals: 1,
  isDouble: true,
  points: 6,
  exact: true,
);

H2hCupBoardDto _board(List<H2hCupBoardFixtureDto> fixtures) => H2hCupBoardDto(
  monthStart: '2026-11-01',
  paths: [
    H2hCupBoardPathDto(
      place: 1,
      stages: [
        H2hCupBoardStageDto(
          round: 'semi',
          cupDay: 1,
          phase: 'live',
          attempt: 1,
          day: '2026-11-20',
          pairs: [
            H2hCupBoardPairDto(
              slot: 1,
              home: _alice,
              away: _bob,
              decided: false,
              fixtures: fixtures,
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('H2hCupBoardDto', () {
    const started = H2hCupBoardFixtureDto(
      fixtureId: 'f-1',
      homeTeam: 'Bayern',
      awayTeam: 'Dortmund',
      homeTeamId: 't-1',
      awayTeamId: 't-2',
      kickoffAt: '2026-11-20T10:30:00.000Z',
      state: 'finished',
      homeGoals: 2,
      awayGoals: 1,
      homeSide: H2hCupBoardSideDto(revealed: true, pick: _pick),
      awaySide: H2hCupBoardSideDto(revealed: true),
    );

    const notStarted = H2hCupBoardFixtureDto(
      fixtureId: 'f-2',
      homeTeam: 'Real Madrid',
      awayTeam: 'Villarreal',
      kickoffAt: '2026-11-20T19:00:00.000Z',
      state: 'not_started',
      homeSide: H2hCupBoardSideDto(revealed: true, pick: _pick),
      awaySide: H2hCupBoardSideDto.hidden(),
    );

    test('survives a JSON round trip unchanged', () {
      final board = _board(const [started, notStarted]);
      final json = _wire(board.toJson());
      expect(H2hCupBoardDto.fromJson(json).toJson(), board.toJson());
      expect(json['schema_version'], H2hCupBoardDto.currentSchemaVersion);
    });

    test('a visible side with no pick means not predicted', () {
      final json = _wire(started.toJson());
      final away = json['away_side']! as Map<String, Object?>;
      expect(away, {'revealed': true});
      final back = H2hCupBoardFixtureDto.fromJson(json);
      expect(back.awaySide.revealed, isTrue);
      expect(back.awaySide.pick, isNull);
      expect(back.homeSide.pick?.homeGoals, 2);
    });

    test('a withheld side is `revealed` false and nothing else', () {
      final json = _wire(notStarted.toJson());
      expect(json['away_side'], {'revealed': false});
      expect(json['home_side'], contains('pick'));
    });

    test('a board of withheld sides carries no pick key anywhere', () {
      const hiddenFixture = H2hCupBoardFixtureDto(
        fixtureId: 'f-3',
        homeTeam: 'Inter',
        awayTeam: 'Napoli',
        kickoffAt: '2026-11-20T21:00:00.000Z',
        state: 'not_started',
        homeSide: H2hCupBoardSideDto.hidden(),
        awaySide: H2hCupBoardSideDto.hidden(),
      );
      final text = jsonEncode(_board(const [hiddenFixture]).toJson());
      expect(text, isNot(contains('"pick"')));
      expect(text, isNot(contains('is_double')));
      expect(text, isNot(contains('"exact"')));
      expect(text, isNot(contains('"points"')));
      expect(text, isNot(contains('home_goals')));
    });

    test('a withheld side looks the same however it was built', () {
      const viaFactory = H2hCupBoardSideDto.hidden();
      const viaFlag = H2hCupBoardSideDto(revealed: false);
      expect(jsonEncode(viaFactory.toJson()), jsonEncode(viaFlag.toJson()));
      expect(jsonEncode(viaFactory.toJson()), '{"revealed":false}');
    });

    test('a pick on a withheld side is dropped on read, never written', () {
      final side = H2hCupBoardSideDto.fromJson(const {
        'revealed': false,
        'pick': {'home_goals': 3, 'away_goals': 0, 'is_double': false},
      });
      expect(side.revealed, isFalse);
      expect(side.pick, isNull);
      expect(side.toJson(), {'revealed': false});
    });

    test('a payload that does not say revealed reads as withheld', () {
      final side = H2hCupBoardSideDto.fromJson(const {
        'pick': {'home_goals': 1, 'away_goals': 1, 'is_double': false},
      });
      expect(side.revealed, isFalse);
      expect(side.pick, isNull);
      final fixture = H2hCupBoardFixtureDto.fromJson(const {
        'fixture_id': 'f-9',
      });
      expect(fixture.homeSide.revealed, isFalse);
      expect(fixture.awaySide.revealed, isFalse);
      expect(fixture.state, 'not_started');
    });

    test('a withheld side cannot be built with a pick', () {
      H2hCupBoardSideDto build({required bool revealed}) =>
          H2hCupBoardSideDto(revealed: revealed, pick: _pick);
      expect(build(revealed: true).pick, isNotNull);
      expect(() => build(revealed: false), throwsA(isA<AssertionError>()));
    });

    test('a fixture with no kickoff and no result keeps those keys out', () {
      const bare = H2hCupBoardFixtureDto(
        fixtureId: 'f-4',
        homeTeam: 'A',
        awayTeam: 'B',
        state: 'not_started',
        homeSide: H2hCupBoardSideDto.hidden(),
        awaySide: H2hCupBoardSideDto.hidden(),
      );
      final json = bare.toJson();
      expect(json.containsKey('kickoff_at'), isFalse);
      expect(json.containsKey('home_goals'), isFalse);
      expect(json.containsKey('home_team_id'), isFalse);
    });

    test('a stage keeps its bye and a path its title', () {
      const board = H2hCupBoardDto(
        monthStart: '2026-11-01',
        paths: [
          H2hCupBoardPathDto(
            place: 2,
            stages: [
              H2hCupBoardStageDto(
                round: 'final',
                cupDay: 3,
                phase: 'decided',
                attempt: 2,
                pairs: [],
                bye: _bob,
              ),
            ],
            title: H2hCupTitleDto(how: 'final', champion: _alice),
          ),
        ],
      );
      final back = H2hCupBoardDto.fromJson(_wire(board.toJson()));
      expect(back.paths.single.stages.single.bye?.userId, 'u-2');
      expect(back.paths.single.stages.single.attempt, 2);
      expect(back.paths.single.title?.champion?.userId, 'u-1');
    });

    test('an empty or old payload reads as a cup that does not stand', () {
      final board = H2hCupBoardDto.fromJson(const {});
      expect(board.monthStart, isNull);
      expect(board.paths, isEmpty);
      expect(board.schemaVersion, 1);
      expect(_wire(const H2hCupBoardDto().toJson()), {
        'schema_version': 1,
        'paths': <Object?>[],
      });
    });
  });
}
