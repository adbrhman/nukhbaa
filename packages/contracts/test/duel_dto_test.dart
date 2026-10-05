import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('a create request leaves out an absent target and capacity', () {
    const dto = CreateDuelChallengeRequestDto(seasonId: 's', fixtureId: 'f');
    final json = dto.toJson();
    expect(json.containsKey('capacity'), isFalse);
    expect(json.containsKey('target_user_id'), isFalse);
    final back = CreateDuelChallengeRequestDto.fromJson(json);
    expect(back.seasonId, 's');
    expect(back.fixtureId, 'f');
    expect(back.capacity, isNull);
  });

  test('a create request of the wrong types reads as empty, never throws', () {
    final dto = CreateDuelChallengeRequestDto.fromJson(const {
      'season_id': 1,
      'fixture_id': true,
      'capacity': '5',
      'target_user_id': 7,
    });
    expect(dto.seasonId, '');
    expect(dto.fixtureId, '');
    expect(dto.capacity, isNull);
    expect(dto.targetUserId, isNull);
  });

  test('an accept request round-trips', () {
    const dto = AcceptDuelChallengeRequestDto(
      homeGoals: 2,
      awayGoals: 1,
      isDouble: true,
    );
    final back = AcceptDuelChallengeRequestDto.fromJson(dto.toJson());
    expect(back.homeGoals, 2);
    expect(back.awayGoals, 1);
    expect(back.isDouble, isTrue);
  });

  test('MyDuelsDto round-trips through JSON text', () {
    const dto = MyDuelsDto(
      challenges: [
        DuelChallengeDto(
          id: 'c',
          code: 'ABCDEFGHJKMN',
          seasonId: 's',
          fixtureId: 'f',
          homeTeam: 'Home',
          awayTeam: 'Away',
          kickoffAt: '2026-10-05T18:00:00.000Z',
          challengerUserId: 'u',
          challengerName: 'Ali',
          isPrivate: true,
          capacity: 1,
          acceptedCount: 0,
          state: 'open',
          isMine: false,
          isForMe: true,
        ),
      ],
      duels: [
        DuelSummaryDto(
          id: 'd',
          challengeId: 'c',
          fixtureId: 'f',
          homeTeam: 'Home',
          awayTeam: 'Away',
          kickoffAt: '2026-10-05T18:00:00.000Z',
          acceptedAt: '2026-10-05T12:00:00.000Z',
          isChallenger: true,
          opponentUserId: 'o',
          opponentName: 'Badr',
          myHomeGoals: 2,
          myAwayGoals: 1,
          myIsDouble: false,
          state: 'upcoming',
        ),
      ],
    );
    final decoded =
        jsonDecode(jsonEncode(dto.toJson())) as Map<String, Object?>;
    final back = MyDuelsDto.fromJson(decoded);

    final challenge = back.challenges.single;
    expect(challenge.code, 'ABCDEFGHJKMN');
    expect(challenge.isPrivate, isTrue);
    expect(challenge.isForMe, isTrue);
    expect(challenge.state, 'open');

    final duel = back.duels.single;
    expect(duel.opponentName, 'Badr');
    expect(duel.myHomeGoals, 2);
    expect(duel.opponentHomeGoals, isNull);
    expect(duel.outcome, isNull);
    expect(duel.state, 'upcoming');
  });
}
