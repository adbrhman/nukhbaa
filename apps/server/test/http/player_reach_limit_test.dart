import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:server/http/rate_limit.dart';
import 'package:test/test.dart';

/// What one player does that rings another player's phone is counted per
/// player over 24 hours, only when it succeeded, and refused with an Arabic
/// `409` the app shows as it is (audit M-20).
void main() {
  group('RateLimiter.blockedFor', () {
    test('counts nothing, and answers only once the limit is used', () {
      var now = DateTime.utc(2026, 10, 15, 12);
      final limiter = RateLimiter(
        limit: 2,
        window: const Duration(hours: 24),
        clock: () => now,
      );

      expect(limiter.blockedFor('k'), isNull);
      expect(limiter.blockedFor('k'), isNull);
      expect(limiter.hit('k'), isNull);
      expect(limiter.blockedFor('k'), isNull);
      expect(limiter.hit('k'), isNull);
      expect(limiter.blockedFor('k'), const Duration(hours: 24));
      expect(limiter.blockedFor('other'), isNull);

      now = now.add(const Duration(hours: 24));
      expect(limiter.blockedFor('k'), isNull);
    });
  });

  group('limitPlayerReach', () {
    const player = AuthenticatedUser(
      userId: UserId('5e5e5e5e-0000-4000-8000-0000000001a1'),
      role: PlatformRole.user,
    );

    test('three private challenges to one player in 24 hours, then an '
        'Arabic 409; another player can still be challenged', () async {
      for (var i = 0; i < 3; i++) {
        expect(
          limitPlayerReach(
            PlayerReach.privateChallenge,
            player,
            target: 'rival-a',
          ),
          isNull,
        );
        countPlayerReach(
          PlayerReach.privateChallenge,
          player,
          target: 'rival-a',
        );
      }

      final refused = limitPlayerReach(
        PlayerReach.privateChallenge,
        player,
        target: 'rival-a',
      );

      expect(refused, isNotNull);
      expect(refused!.statusCode, HttpStatus.conflict);
      final body = jsonDecode(await refused.body()) as Map<String, Object?>;
      expect(body['code'], 'social.daily_limit');
      expect(body['message'], contains('24'));
      expect(
        limitPlayerReach(
          PlayerReach.privateChallenge,
          player,
          target: 'rival-b',
        ),
        isNull,
      );
    });

    test('thirty invitations, then a refusal; a check alone counts '
        'nothing', () {
      const inviter = AuthenticatedUser(
        userId: UserId('5e5e5e5e-0000-4000-8000-0000000001a2'),
        role: PlatformRole.user,
      );
      for (var i = 0; i < 50; i++) {
        expect(limitPlayerReach(PlayerReach.groupInvite, inviter), isNull);
      }
      for (var i = 0; i < 30; i++) {
        countPlayerReach(PlayerReach.groupInvite, inviter);
      }

      expect(limitPlayerReach(PlayerReach.groupInvite, inviter), isNotNull);
    });

    test('an admin is never counted or refused', () {
      const admin = AuthenticatedUser(
        userId: UserId('5e5e5e5e-0000-4000-8000-0000000001a3'),
        role: PlatformRole.admin,
      );
      for (var i = 0; i < 10; i++) {
        countPlayerReach(PlayerReach.groupCreate, admin);
      }

      expect(limitPlayerReach(PlayerReach.groupCreate, admin), isNull);
    });
  });
}
