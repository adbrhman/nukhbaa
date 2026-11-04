/// Wire shapes of the sports publisher's admin routes (`/admin/publisher`,
/// migration 0200). Every `fromJson` tolerates missing keys.
library;

String _s(Object? value) => value is String ? value : '';

String? _sn(Object? value) => value is String ? value : null;

int? _in(Object? value) => value is int ? value : null;

List<Map<String, Object?>> _maps(Object? value) => <Map<String, Object?>>[
  if (value is List<Object?>)
    for (final item in value)
      if (item is Map<String, Object?>) item,
];

/// One platform's setting: `GET /admin/publisher` lists them, `PUT
/// /admin/publisher` takes one.
final class PublisherSettingDto {
  /// Creates the setting.
  const PublisherSettingDto({
    required this.platform,
    required this.enabled,
    required this.goals,
    required this.finalResult,
    required this.holdSeconds,
    required this.minGapSeconds,
    required this.dailyCap,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherSettingDto.fromJson(Map<String, Object?> json) =>
      PublisherSettingDto(
        platform: _s(json['platform']),
        enabled: json['enabled'] == true,
        goals: _s(json['goals']).isEmpty ? 'all' : _s(json['goals']),
        finalResult: json['final_result'] != false,
        holdSeconds: _in(json['hold_seconds']) ?? 180,
        minGapSeconds: _in(json['min_gap_seconds']) ?? 0,
        dailyCap: _in(json['daily_cap']) ?? 0,
      );

  /// `facebook`, `instagram` or `x`.
  final String platform;

  /// Whether the platform is posted to.
  final bool enabled;

  /// `all`, `key` or `none`.
  final String goals;

  /// Whether the final result is posted.
  final bool finalResult;

  /// How long a goal must stand before it is posted.
  final int holdSeconds;

  /// The least time between two goal posts.
  final int minGapSeconds;

  /// The most goal posts in a day.
  final int dailyCap;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'enabled': enabled,
    'goals': goals,
    'final_result': finalResult,
    'hold_seconds': holdSeconds,
    'min_gap_seconds': minGapSeconds,
    'daily_cap': dailyCap,
  };
}

/// A match the admin may pick.
final class PublisherCandidateDto {
  /// Creates the candidate.
  const PublisherCandidateDto({
    required this.fixtureId,
    required this.homeName,
    required this.awayName,
    required this.leagueName,
    required this.kickoffAt,
    required this.covered,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherCandidateDto.fromJson(Map<String, Object?> json) =>
      PublisherCandidateDto(
        fixtureId: _s(json['fixture_id']),
        homeName: _s(json['home_name']),
        awayName: _s(json['away_name']),
        leagueName: _s(json['league_name']),
        kickoffAt: _s(json['kickoff_at']),
        covered: json['covered'] == true,
      );

  /// The fixture id.
  final String fixtureId;

  /// The home club.
  final String homeName;

  /// The away club.
  final String awayName;

  /// The competition; empty when none.
  final String leagueName;

  /// Kickoff, ISO-8601 UTC.
  final String kickoffAt;

  /// Whether it is covered.
  final bool covered;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'fixture_id': fixtureId,
    'home_name': homeName,
    'away_name': awayName,
    'league_name': leagueName,
    'kickoff_at': kickoffAt,
    'covered': covered,
  };
}

/// A post as the panel lists it.
final class PublisherPostDto {
  /// Creates the post.
  const PublisherPostDto({
    required this.id,
    required this.fixtureId,
    required this.matchLabel,
    required this.kind,
    required this.platform,
    required this.state,
    required this.body,
    required this.hasCard,
    required this.createdAt,
    required this.attempts,
    this.externalId,
    this.error,
    this.publishedAt,
    this.reach,
    this.reactions,
    this.comments,
    this.shares,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherPostDto.fromJson(Map<String, Object?> json) =>
      PublisherPostDto(
        id: _s(json['id']),
        fixtureId: _s(json['fixture_id']),
        matchLabel: _s(json['match_label']),
        kind: _s(json['kind']),
        platform: _s(json['platform']),
        state: _s(json['state']),
        body: _s(json['body']),
        hasCard: json['has_card'] == true,
        createdAt: _s(json['created_at']),
        attempts: _in(json['attempts']) ?? 0,
        externalId: _sn(json['external_id']),
        error: _sn(json['error']),
        publishedAt: _sn(json['published_at']),
        reach: _in(json['reach']),
        reactions: _in(json['reactions']),
        comments: _in(json['comments']),
        shares: _in(json['shares']),
      );

  /// Its id.
  final String id;

  /// Its match.
  final String fixtureId;

  /// «الهلال - النصر».
  final String matchLabel;

  /// `goal`, `final` or `correction`.
  final String kind;

  /// `facebook`, `instagram` or `x`.
  final String platform;

  /// `queued`, `published`, `dry_run`, `ready_to_share`, `shared`,
  /// `failed`, `uncertain`, `skipped` or `cancelled`.
  final String state;

  /// The words.
  final String body;

  /// Whether it has a picture (`GET /admin/publisher/posts/{id}/card`).
  final bool hasCard;

  /// When it was queued, ISO-8601 UTC.
  final String createdAt;

  /// When it went out, ISO-8601 UTC.
  final String? publishedAt;

  /// The attempts made.
  final int attempts;

  /// The platform's id.
  final String? externalId;

  /// The last error.
  final String? error;

  /// Accounts reached.
  final int? reach;

  /// Reactions or likes.
  final int? reactions;

  /// Comments.
  final int? comments;

  /// Shares.
  final int? shares;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fixture_id': fixtureId,
    'match_label': matchLabel,
    'kind': kind,
    'platform': platform,
    'state': state,
    'body': body,
    'has_card': hasCard,
    'created_at': createdAt,
    'published_at': publishedAt,
    'attempts': attempts,
    'external_id': externalId,
    'error': error,
    'reach': reach,
    'reactions': reactions,
    'comments': comments,
    'shares': shares,
  };
}

/// A club's disc colour and label.
final class PublisherBadgeDto {
  /// Creates the badge.
  const PublisherBadgeDto({
    required this.teamId,
    required this.teamName,
    required this.fill,
    this.label,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherBadgeDto.fromJson(Map<String, Object?> json) =>
      PublisherBadgeDto(
        teamId: _s(json['team_id']),
        teamName: _s(json['team_name']),
        fill: _s(json['fill']),
        label: _sn(json['label']),
      );

  /// The club's catalog id.
  final String teamId;

  /// The club's name.
  final String teamName;

  /// `#RRGGBB`.
  final String fill;

  /// The words on the disc, when set.
  final String? label;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'team_id': teamId,
    'team_name': teamName,
    'fill': fill,
    'label': label,
  };
}

/// `GET /admin/publisher`: everything the panel shows.
final class PublisherOverviewDto {
  /// Creates the overview.
  const PublisherOverviewDto({
    required this.mode,
    required this.settings,
    required this.candidates,
    required this.posts,
    required this.badges,
    required this.linked,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherOverviewDto.fromJson(Map<String, Object?> json) =>
      PublisherOverviewDto(
        mode: _s(json['mode']).isEmpty ? 'off' : _s(json['mode']),
        settings: <PublisherSettingDto>[
          for (final item in _maps(json['settings']))
            PublisherSettingDto.fromJson(item),
        ],
        candidates: <PublisherCandidateDto>[
          for (final item in _maps(json['candidates']))
            PublisherCandidateDto.fromJson(item),
        ],
        posts: <PublisherPostDto>[
          for (final item in _maps(json['posts']))
            PublisherPostDto.fromJson(item),
        ],
        badges: <PublisherBadgeDto>[
          for (final item in _maps(json['badges']))
            PublisherBadgeDto.fromJson(item),
        ],
        linked: <String>[
          if (json['linked'] case final List<Object?> raw)
            for (final item in raw)
              if (item is String) item,
        ],
      );

  /// `off`, `dry_run` or `on`.
  final String mode;

  /// Each platform's setting.
  final List<PublisherSettingDto> settings;

  /// The matches to pick from.
  final List<PublisherCandidateDto> candidates;

  /// The latest posts.
  final List<PublisherPostDto> posts;

  /// The club colours set.
  final List<PublisherBadgeDto> badges;

  /// The platforms the server holds an account for.
  final List<String> linked;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode,
    'settings': <Object?>[for (final s in settings) s.toJson()],
    'candidates': <Object?>[for (final c in candidates) c.toJson()],
    'posts': <Object?>[for (final p in posts) p.toJson()],
    'badges': <Object?>[for (final b in badges) b.toJson()],
    'linked': linked,
  };
}

/// `GET /admin/publisher/accounts`: whose account each token opens.
final class PublisherAccountDto {
  /// Creates the check.
  const PublisherAccountDto({
    required this.platform,
    required this.ok,
    required this.detail,
  });

  /// Deserializes, tolerating missing keys.
  factory PublisherAccountDto.fromJson(Map<String, Object?> json) =>
      PublisherAccountDto(
        platform: _s(json['platform']),
        ok: json['ok'] == true,
        detail: _s(json['detail']),
      );

  /// The platform.
  final String platform;

  /// Whether the token works.
  final bool ok;

  /// The account's name, or why it failed.
  final String detail;

  /// Serializes.
  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'ok': ok,
    'detail': detail,
  };
}
