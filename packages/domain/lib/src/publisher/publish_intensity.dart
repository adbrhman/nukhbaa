import 'package:domain/src/publisher/goal_moment.dart';
import 'package:domain/src/publisher/publish_platform.dart';

/// Which goals a platform posts.
enum GoalCoverage {
  /// Every confirmed goal (the owner's default, 2026-11-04).
  all('all'),

  /// Only goals that open, level or turn a match ([GoalMoment.key]).
  key('key'),

  /// No goal; the final result only.
  none('none');

  const GoalCoverage(this.wire);

  /// The stored name. A storage contract: never renamed.
  final String wire;

  /// The coverage named [wire]; null for a name not known here.
  static GoalCoverage? fromWire(String wire) {
    for (final coverage in GoalCoverage.values) {
      if (coverage.wire == wire) {
        return coverage;
      }
    }
    return null;
  }
}

/// How much one platform posts, set by an admin.
final class PlatformIntensity {
  /// Creates the setting.
  const PlatformIntensity({
    required this.platform,
    required this.enabled,
    required this.goals,
    required this.finalResult,
    required this.hold,
    required this.minGap,
    required this.dailyCap,
  });

  /// The defaults (proposed with the plan, approved 2026-11-04): every goal
  /// and the final result on all three; a goal posted once it has stood
  /// three minutes, eight on Instagram, whose publishing API offers no way
  /// to correct a post the VAR later cancels; at most 12 goal posts a day on
  /// Facebook, 8 on Instagram, 20 prepared for X. Every platform starts off
  /// until an admin turns it on.
  factory PlatformIntensity.defaults(PublishPlatform platform) =>
      switch (platform) {
        PublishPlatform.facebook => const PlatformIntensity(
          platform: PublishPlatform.facebook,
          enabled: false,
          goals: GoalCoverage.all,
          finalResult: true,
          hold: Duration(minutes: 3),
          minGap: Duration.zero,
          dailyCap: 12,
        ),
        PublishPlatform.instagram => const PlatformIntensity(
          platform: PublishPlatform.instagram,
          enabled: false,
          goals: GoalCoverage.all,
          finalResult: true,
          hold: Duration(minutes: 8),
          minGap: Duration.zero,
          dailyCap: 8,
        ),
        PublishPlatform.x => const PlatformIntensity(
          platform: PublishPlatform.x,
          enabled: false,
          goals: GoalCoverage.all,
          finalResult: true,
          hold: Duration(minutes: 3),
          minGap: Duration.zero,
          dailyCap: 20,
        ),
      };

  /// The platform.
  final PublishPlatform platform;

  /// Whether the platform is posted to at all.
  final bool enabled;

  /// Which goals it posts.
  final GoalCoverage goals;

  /// Whether it posts the final result.
  final bool finalResult;

  /// How long a goal must have stood on the feed before it is posted here.
  final Duration hold;

  /// The least time between two goal posts here; a goal that comes sooner
  /// waits for it.
  final Duration minGap;

  /// The most goal posts here in one Riyadh day. Final results are not
  /// counted against it and never held back by it.
  final int dailyCap;

  /// Whether a goal that meant [moment] is posted here.
  bool admits(GoalMoment moment) =>
      enabled &&
      switch (goals) {
        GoalCoverage.all => true,
        GoalCoverage.key => moment.key,
        GoalCoverage.none => false,
      };

  /// This setting with the fields given replaced.
  PlatformIntensity copyWith({
    bool? enabled,
    GoalCoverage? goals,
    bool? finalResult,
    Duration? hold,
    Duration? minGap,
    int? dailyCap,
  }) => PlatformIntensity(
    platform: platform,
    enabled: enabled ?? this.enabled,
    goals: goals ?? this.goals,
    finalResult: finalResult ?? this.finalResult,
    hold: hold ?? this.hold,
    minGap: minGap ?? this.minGap,
    dailyCap: dailyCap ?? this.dailyCap,
  );

  /// Bounds an admin may set: [hold] from 1 to 30 minutes, [minGap] up to
  /// 60 minutes, [dailyCap] from 0 to 50. Null when within them, else the
  /// field out of bounds.
  String? outOfBounds() {
    if (hold < const Duration(minutes: 1) ||
        hold > const Duration(minutes: 30)) {
      return 'hold';
    }
    if (minGap.isNegative || minGap > const Duration(minutes: 60)) {
      return 'min_gap';
    }
    if (dailyCap < 0 || dailyCap > 50) {
      return 'daily_cap';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformIntensity &&
      other.platform == platform &&
      other.enabled == enabled &&
      other.goals == goals &&
      other.finalResult == finalResult &&
      other.hold == hold &&
      other.minGap == minGap &&
      other.dailyCap == dailyCap;

  @override
  int get hashCode => Object.hash(
    platform,
    enabled,
    goals,
    finalResult,
    hold,
    minGap,
    dailyCap,
  );
}

/// What the gate says about a goal post that is due.
sealed class GoalGateDecision {
  const GoalGateDecision();
}

/// Post it now.
final class GoalGateOpen extends GoalGateDecision {
  /// Creates the decision.
  const GoalGateOpen();
}

/// Post it at [at], once the platform's least gap has passed.
final class GoalGateWait extends GoalGateDecision {
  /// Creates the decision.
  const GoalGateWait(this.at);

  /// When it may go out.
  final DateTime at;
}

/// Do not post it: the platform's day is full.
final class GoalGateFull extends GoalGateDecision {
  /// Creates the decision.
  const GoalGateFull();
}

/// The daily cap and the least gap of one platform, applied to a goal post
/// that is due (pure, the clock passed in).
final class GoalGate {
  const GoalGate._();

  /// The decision at [now] for [intensity]'s platform, which has posted
  /// [goalPostsToday] goal posts this Riyadh day, the last at
  /// [lastGoalPostAt] (null when none).
  static GoalGateDecision decide({
    required PlatformIntensity intensity,
    required int goalPostsToday,
    required DateTime? lastGoalPostAt,
    required DateTime now,
  }) {
    if (goalPostsToday >= intensity.dailyCap) {
      return const GoalGateFull();
    }
    if (lastGoalPostAt != null && intensity.minGap > Duration.zero) {
      final at = lastGoalPostAt.add(intensity.minGap);
      if (at.isAfter(now)) {
        return GoalGateWait(at);
      }
    }
    return const GoalGateOpen();
  }
}
