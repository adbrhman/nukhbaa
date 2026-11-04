import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('PlatformIntensity.defaults', () {
    test('every platform starts off, posting every goal and the result', () {
      for (final platform in PublishPlatform.values) {
        final intensity = PlatformIntensity.defaults(platform);

        expect(intensity.platform, platform);
        expect(intensity.enabled, isFalse, reason: platform.wire);
        expect(intensity.goals, GoalCoverage.all, reason: platform.wire);
        expect(intensity.finalResult, isTrue, reason: platform.wire);
        expect(intensity.outOfBounds(), isNull, reason: platform.wire);
      }
    });

    test('Instagram waits longer than the others before a goal', () {
      final instagram = PlatformIntensity.defaults(PublishPlatform.instagram);
      final facebook = PlatformIntensity.defaults(PublishPlatform.facebook);

      expect(instagram.hold, greaterThan(facebook.hold));
    });

    test('X is prepared for an admin to share, the others are posted', () {
      expect(PublishPlatform.x.delivery, PublishDelivery.manualShare);
      expect(PublishPlatform.facebook.delivery, PublishDelivery.automatic);
      expect(PublishPlatform.instagram.delivery, PublishDelivery.automatic);
    });
  });

  group('PlatformIntensity.admits', () {
    final posting = PlatformIntensity.defaults(
      PublishPlatform.facebook,
    ).copyWith(enabled: true);

    test('all posts every goal', () {
      for (final moment in GoalMoment.values) {
        expect(posting.admits(moment), isTrue, reason: moment.wire);
      }
    });

    test('key posts only the goals that open, level or turn a match', () {
      final key = posting.copyWith(goals: GoalCoverage.key);

      expect(key.admits(GoalMoment.opener), isTrue);
      expect(key.admits(GoalMoment.lateWinner), isTrue);
      expect(key.admits(GoalMoment.extendsLead), isFalse);
      expect(key.admits(GoalMoment.reducesDeficit), isFalse);
    });

    test('none and a platform turned off post no goal', () {
      final none = posting.copyWith(goals: GoalCoverage.none);
      final off = posting.copyWith(enabled: false);

      for (final moment in GoalMoment.values) {
        expect(none.admits(moment), isFalse);
        expect(off.admits(moment), isFalse);
      }
    });
  });

  group('PlatformIntensity.outOfBounds', () {
    final base = PlatformIntensity.defaults(PublishPlatform.facebook);

    test('names the field an admin set out of bounds', () {
      expect(base.copyWith(hold: Duration.zero).outOfBounds(), 'hold');
      expect(
        base.copyWith(minGap: const Duration(hours: 2)).outOfBounds(),
        'min_gap',
      );
      expect(base.copyWith(dailyCap: 51).outOfBounds(), 'daily_cap');
      expect(base.copyWith(dailyCap: -1).outOfBounds(), 'daily_cap');
    });
  });

  group('GoalGate.decide', () {
    final now = DateTime.utc(2026, 11, 7, 19);
    final intensity = PlatformIntensity.defaults(
      PublishPlatform.facebook,
    ).copyWith(enabled: true, minGap: const Duration(minutes: 10));

    test('opens when the day has room and the gap has passed', () {
      expect(
        GoalGate.decide(
          intensity: intensity,
          goalPostsToday: 3,
          lastGoalPostAt: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isA<GoalGateOpen>(),
      );
    });

    test('waits for the least gap after the last goal post', () {
      final decision = GoalGate.decide(
        intensity: intensity,
        goalPostsToday: 3,
        lastGoalPostAt: now.subtract(const Duration(minutes: 4)),
        now: now,
      );

      expect(decision, isA<GoalGateWait>());
      expect(
        (decision as GoalGateWait).at,
        now.add(const Duration(minutes: 6)),
      );
    });

    test('is full once the day reached the cap', () {
      expect(
        GoalGate.decide(
          intensity: intensity,
          goalPostsToday: intensity.dailyCap,
          lastGoalPostAt: null,
          now: now,
        ),
        isA<GoalGateFull>(),
      );
    });
  });

  test('every coverage and platform reads back from its stored name', () {
    for (final coverage in GoalCoverage.values) {
      expect(GoalCoverage.fromWire(coverage.wire), coverage);
    }
    for (final platform in PublishPlatform.values) {
      expect(PublishPlatform.fromWire(platform.wire), platform);
    }
    expect(PublishPlatform.fromWire('tiktok'), isNull);
  });
}
