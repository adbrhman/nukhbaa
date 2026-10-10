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

    test('a match not started carries no points and no winner', () {
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
