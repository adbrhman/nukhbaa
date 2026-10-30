import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// Sends [json] through a real JSON round trip, as the wire does.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
        .cast<String, Object?>();

void main() {
  group('H2hGroupRoundDto', () {
    const dto = H2hGroupRoundDto(
      round: 3,
      day: '2026-10-13',
      status: 'live',
      matches: [
        H2hGroupMatchDto(
          homeUserId: 'u-me',
          homeName: 'سامي',
          homeIsMe: true,
          homePoints: 12,
          awayUserId: 'u-2',
          awayName: 'نورة',
          awayAvatarUrl: '/users/u-2/avatar?v=1',
          awayPoints: 9,
          winner: 'home',
        ),
        H2hGroupMatchDto(
          homeUserId: 'u-3',
          homeName: 'عمر',
          homePoints: 4,
          awayPoints: 6.5,
          winner: 'away',
        ),
      ],
    );

    test('survives the wire unchanged', () {
      final back = H2hGroupRoundDto.fromJson(_wire(dto.toJson()));

      expect(back.toJson(), dto.toJson());
      expect(back.matches.first.homeIsMe, isTrue);
      expect(back.matches.last.awayUserId, isNull);
      expect(back.matches.last.awayPoints, 6.5);
    });

    test('a whole average arrives as an int and is read as a double', () {
      final back = H2hGroupRoundDto.fromJson(
        _wire(<String, Object?>{
          'round': 1,
          'matches': [
            <String, Object?>{'home_user_id': 'u-1', 'away_points': 7},
          ],
        }),
      );

      expect(back.matches.single.awayPoints, 7.0);
      expect(back.status, 'upcoming');
      expect(back.schemaVersion, 1);
    });

    test('secret pairs say so; old payloads read not secret', () {
      const round = H2hGroupRoundDto(
        round: 3,
        day: '2026-11-07',
        status: 'open',
        matches: [],
        matchesHidden: true,
      );
      final json = _wire(round.toJson());
      expect(json['matches_hidden'], isTrue);
      expect(json['reveals_at'], isNull);
      expect(H2hGroupRoundDto.fromJson(json).matchesHidden, isTrue);
      expect(
        H2hGroupRoundDto.fromJson(const {'round': 1}).matchesHidden,
        isFalse,
      );
    });

    // NK172 group match absence contract test
    test('an absent away member is explicit and old matches default false', () {
      const match = H2hGroupMatchDto(
        homeUserId: 'u-1',
        homeName: 'A',
        homePoints: 6,
        awayUserId: 'u-2',
        awayName: 'B',
        awayPoints: 2.5,
        winner: 'home',
        awayAbsent: true,
      );
      final json = _wire(match.toJson());
      expect(json['away_absent'], isTrue);
      expect(H2hGroupMatchDto.fromJson(json).awayAbsent, isTrue);
      expect(
        H2hGroupMatchDto.fromJson(const {'home_user_id': 'u-1'}).awayAbsent,
        isFalse,
      );
    });

    test('a match not started carries no points and no winner', () {
      // NK172_090
      final back = H2hGroupMatchDto.fromJson(
        _wire(<String, Object?>{
          'home_user_id': 'u-1',
          'home_name': 'أ',
          'away_user_id': 'u-2',
          'away_name': 'ب',
        }),
      );

      expect(back.homePoints, isNull);
      expect(back.awayPoints, isNull);
      expect(back.winner, isNull);
      expect(back.homeIsMe, isFalse);
    });
  });
}
