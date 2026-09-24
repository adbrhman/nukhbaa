/// Body of `POST /me/frame-report` (migration 0070): one app session's
/// frame counts.
final class FrameReportDto {
  /// Creates the report.
  const FrameReportDto({
    required this.build,
    required this.platform,
    required this.refreshRateHz,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
    required this.worstFrameMs,
    this.deviceModel,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FrameReportDto.fromJson(Map<String, Object?> json) => FrameReportDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    build: (json['build'] as String?) ?? '',
    platform: (json['platform'] as String?) ?? '',
    refreshRateHz: (json['refresh_rate_hz'] as int?) ?? 0,
    frames: (json['frames'] as int?) ?? 0,
    slowFrames: (json['slow_frames'] as int?) ?? 0,
    frozenFrames: (json['frozen_frames'] as int?) ?? 0,
    worstFrameMs: (json['worst_frame_ms'] as int?) ?? 0,
    deviceModel: json['device_model'] as String?,
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The build's short commit sha.
  final String build;

  /// `android`, `ios` or `web`.
  final String platform;

  /// The display's refresh rate the frames were measured against.
  final int refreshRateHz;

  /// Frames drawn in the session.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms.
  final int frozenFrames;

  /// The slowest frame, in milliseconds.
  final int worstFrameMs;

  /// The device's maker and model (migration 0071); omitted when unknown.
  final String? deviceModel;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'build': build,
    'platform': platform,
    'refresh_rate_hz': refreshRateHz,
    'frames': frames,
    'slow_frames': slowFrames,
    'frozen_frames': frozenFrames,
    'worst_frame_ms': worstFrameMs,
    if (deviceModel != null) 'device_model': deviceModel,
  };
}

/// Body of the answer to `POST /me/frame-report`.
final class FrameReportAckDto {
  /// Creates the answer.
  const FrameReportAckDto({
    required this.recorded,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FrameReportAckDto.fromJson(Map<String, Object?> json) =>
      FrameReportAckDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        recorded: (json['recorded'] as bool?) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the report was kept.
  final bool recorded;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recorded': recorded,
  };
}

/// Frame totals for every build together ([build] null) or one build on
/// one platform.
final class FrameTotalsDto {
  /// Creates the totals.
  const FrameTotalsDto({
    required this.build,
    required this.reports,
    required this.users,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
    required this.worstFrameMs,
    required this.lastReportedAt,
    this.platform,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FrameTotalsDto.fromJson(Map<String, Object?> json) => FrameTotalsDto(
    build: json['build'] as String?,
    reports: (json['reports'] as int?) ?? 0,
    users: (json['users'] as int?) ?? 0,
    frames: (json['frames'] as int?) ?? 0,
    slowFrames: (json['slow_frames'] as int?) ?? 0,
    frozenFrames: (json['frozen_frames'] as int?) ?? 0,
    worstFrameMs: (json['worst_frame_ms'] as int?) ?? 0,
    lastReportedAt: json['last_reported_at'] as String?,
    platform: json['platform'] as String?,
  );

  /// The build, or null for every build together.
  final String? build;

  /// The platform of this row (`android`, `ios` or `web`); null for every
  /// build together.
  final String? platform;

  /// Session reports summed.
  final int reports;

  /// Distinct users behind them.
  final int users;

  /// Frames drawn.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms.
  final int frozenFrames;

  /// The slowest frame, in milliseconds.
  final int worstFrameMs;

  /// ISO-8601 UTC time of the newest report, or null.
  final String? lastReportedAt;

  /// The share of slow frames, 0..100 with one decimal; 0 with no frames.
  double get slowPercent =>
      frames == 0 ? 0 : (slowFrames * 1000 / frames).round() / 10;

  /// The share of frozen frames, 0..100 with two decimals; 0 with no frames.
  double get frozenPercent =>
      frames == 0 ? 0 : (frozenFrames * 10000 / frames).round() / 100;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'build': build,
    'reports': reports,
    'users': users,
    'frames': frames,
    'slow_frames': slowFrames,
    'frozen_frames': frozenFrames,
    'worst_frame_ms': worstFrameMs,
    'last_reported_at': lastReportedAt,
    if (platform != null) 'platform': platform,
  };
}

/// Frame totals of one device model (migration 0071).
final class DeviceTotalsDto {
  /// Creates the totals.
  const DeviceTotalsDto({
    required this.deviceModel,
    required this.reports,
    required this.users,
    required this.frames,
    required this.slowFrames,
    required this.frozenFrames,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DeviceTotalsDto.fromJson(Map<String, Object?> json) =>
      DeviceTotalsDto(
        deviceModel: (json['device_model'] as String?) ?? '',
        reports: (json['reports'] as int?) ?? 0,
        users: (json['users'] as int?) ?? 0,
        frames: (json['frames'] as int?) ?? 0,
        slowFrames: (json['slow_frames'] as int?) ?? 0,
        frozenFrames: (json['frozen_frames'] as int?) ?? 0,
      );

  /// The maker and model.
  final String deviceModel;

  /// Session reports summed.
  final int reports;

  /// Distinct users behind them.
  final int users;

  /// Frames drawn.
  final int frames;

  /// Frames over one refresh interval.
  final int slowFrames;

  /// Frames over 700 ms.
  final int frozenFrames;

  /// The share of slow frames, 0..100 with one decimal; 0 with no frames.
  double get slowPercent =>
      frames == 0 ? 0 : (slowFrames * 1000 / frames).round() / 10;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'device_model': deviceModel,
    'reports': reports,
    'users': users,
    'frames': frames,
    'slow_frames': slowFrames,
    'frozen_frames': frozenFrames,
  };
}

/// Body of `GET /admin/frame-stats`: frame totals over the last
/// [windowDays] days, overall and for the newest builds.
final class AdminFrameStatsDto {
  /// Creates the stats.
  const AdminFrameStatsDto({
    required this.windowDays,
    required this.overall,
    required this.builds,
    this.devices = const <DeviceTotalsDto>[],
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminFrameStatsDto.fromJson(Map<String, Object?> json) =>
      AdminFrameStatsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        windowDays: (json['window_days'] as int?) ?? 0,
        overall: FrameTotalsDto.fromJson(
          ((json['overall'] as Map<Object?, Object?>?) ??
                  const <Object?, Object?>{})
              .cast<String, Object?>(),
        ),
        builds: [
          for (final Object? b
              in (json['builds'] as List<Object?>?) ?? const <Object?>[])
            FrameTotalsDto.fromJson(
              (b! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
        devices: [
          for (final Object? d
              in (json['devices'] as List<Object?>?) ?? const <Object?>[])
            DeviceTotalsDto.fromJson(
              (d! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The window's length in days.
  final int windowDays;

  /// Every build together.
  final FrameTotalsDto overall;

  /// The newest builds, one entry per platform each ran on, newest first.
  final List<FrameTotalsDto> builds;

  /// The least smooth device models, each reported by several players.
  final List<DeviceTotalsDto> devices;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'window_days': windowDays,
    'overall': overall.toJson(),
    'builds': [for (final b in builds) b.toJson()],
    'devices': [for (final d in devices) d.toJson()],
  };
}
