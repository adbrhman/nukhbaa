import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// The publisher's admin use-case, or the error a route answers while the
/// server runs without it (`NUKHBA_PUBLISHER` off).
Result<AdminPublisher> adminPublisherOf(CompositionRoot root) {
  final admin = root.adminPublisher;
  if (admin == null) {
    return const Result.err(
      AppError.invariant(
        'publisher.unavailable',
        'النشر الرياضي غير مفعّل على الخادم (NUKHBA_PUBLISHER).',
      ),
    );
  }
  return Result.ok(admin);
}

/// The wire name of [mode].
String publisherModeWire(PublisherMode mode) => switch (mode) {
  PublisherMode.off => 'off',
  PublisherMode.dryRun => 'dry_run',
  PublisherMode.on => 'on',
};

/// [intensity] on the wire.
PublisherSettingDto publisherSettingDto(PlatformIntensity intensity) =>
    PublisherSettingDto(
      platform: intensity.platform.wire,
      enabled: intensity.enabled,
      goals: intensity.goals.wire,
      finalResult: intensity.finalResult,
      holdSeconds: intensity.hold.inSeconds,
      minGapSeconds: intensity.minGap.inSeconds,
      dailyCap: intensity.dailyCap,
    );

/// [dto] as a setting; an error for an unknown platform or coverage.
Result<PlatformIntensity> publisherSettingOf(PublisherSettingDto dto) {
  final platform = PublishPlatform.fromWire(dto.platform);
  final goals = GoalCoverage.fromWire(dto.goals);
  if (platform == null || goals == null) {
    return const Result.err(
      AppError.validation(
        'publisher.setting_invalid',
        'Fields "platform" and "goals" must be known names',
      ),
    );
  }
  return Result.ok(
    PlatformIntensity(
      platform: platform,
      enabled: dto.enabled,
      goals: goals,
      finalResult: dto.finalResult,
      hold: Duration(seconds: dto.holdSeconds),
      minGap: Duration(seconds: dto.minGapSeconds),
      dailyCap: dto.dailyCap,
    ),
  );
}

/// [overview] on the wire.
PublisherOverviewDto publisherOverviewDto(PublisherOverview overview) =>
    PublisherOverviewDto(
      mode: publisherModeWire(overview.mode),
      settings: <PublisherSettingDto>[
        for (final platform in PublishPlatform.values)
          publisherSettingDto(
            overview.settings[platform] ?? PlatformIntensity.defaults(platform),
          ),
      ],
      candidates: <PublisherCandidateDto>[
        for (final candidate in overview.candidates)
          PublisherCandidateDto(
            fixtureId: candidate.fixtureId,
            homeName: candidate.homeName,
            awayName: candidate.awayName,
            leagueName: candidate.leagueName,
            kickoffAt: candidate.kickoffAt.toUtc().toIso8601String(),
            covered: candidate.covered,
          ),
      ],
      posts: <PublisherPostDto>[
        for (final post in overview.posts)
          PublisherPostDto(
            id: post.id,
            fixtureId: post.fixtureId,
            matchLabel: post.matchLabel,
            kind: post.kind.wire,
            platform: post.platform.wire,
            state: post.state.wire,
            body: post.body,
            hasCard: post.cardPath != null,
            createdAt: post.createdAt.toUtc().toIso8601String(),
            publishedAt: post.publishedAt?.toUtc().toIso8601String(),
            attempts: post.attempts,
            externalId: post.externalId,
            error: post.error,
            reach: post.reach,
            reactions: post.reactions,
            comments: post.comments,
            shares: post.shares,
          ),
      ],
      badges: <PublisherBadgeDto>[
        for (final badge in overview.badges)
          PublisherBadgeDto(
            teamId: badge.teamId,
            teamName: badge.teamName,
            fill: badge.fill,
            label: badge.label,
          ),
      ],
      linked: <String>[
        for (final platform in PublishPlatform.values)
          if (overview.linked.contains(platform)) platform.wire,
      ],
    );
