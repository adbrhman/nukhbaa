/// The wire shape of a "latest published build" response
/// (`GET /app/latest-build`).
///
/// [schemaVersion] lets clients and archived payloads evolve safely
/// (API ADR, Section 4). There is deliberately no `version` field: the
/// server's release workflow publishes to a single rolling `latest` tag with
/// no usable semver, so [publishedAt] is the only "is this newer" signal
/// (see `GithubBuildInfoRepository`).
///
/// SCHEMA v2 (In-App OTA): a build may ship one asset PER Android ABI
/// (Flutter `--split-per-abi`), each with its own download URL and SHA-256.
/// The client selects the asset matching the device ABI, downloads it
/// natively (ota_update), verifies the checksum, then triggers the platform
/// package installer. [apkUrl]/[sha256] carry the primary asset for backward
/// compatibility and as a universal fallback. A schema-v1 payload (no
/// `assets`, no `sha256`) still parses: [assets] is empty and [sha256] null.
///
/// Batch 147 adds two optional fields, sent only when known: the release's
/// [buildNumber] (`build_number`, the CI run number) and the oldest build
/// the service still supports, [minSupportedBuild] (`min_supported_build`).
/// An older client ignores both; an older server sends neither.
final class LatestBuildDto {
  /// Creates a latest-build response DTO.
  const LatestBuildDto({
    required this.publishedAt,
    required this.apkUrl,
    this.sha256,
    this.assets = const <BuildAssetDto>[],
    this.buildNumber,
    this.minSupportedBuild,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory LatestBuildDto.fromJson(Map<String, Object?> json) {
    final rawAssets = json['assets'] as List<Object?>? ?? const <Object?>[];
    return LatestBuildDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      publishedAt: json['published_at']! as String,
      apkUrl: json['apk_url']! as String,
      sha256: json['sha256'] as String?,
      assets: rawAssets
          .whereType<Map<String, Object?>>()
          .map(BuildAssetDto.fromJson)
          .toList(growable: false),
      buildNumber: json['build_number'] as int?,
      minSupportedBuild: json['min_supported_build'] as int?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 2;

  /// ISO-8601 timestamp of when the release was published.
  final String publishedAt;

  /// Direct download URL of the primary `.apk` asset (universal or first ABI).
  final String apkUrl;

  /// Lowercase hex SHA-256 of [apkUrl]'s file, when published by CI.
  final String? sha256;

  /// Per-ABI assets (`--split-per-abi`). Empty on a schema-v1 server.
  final List<BuildAssetDto> assets;

  /// The release's build number, when its name carries one.
  final int? buildNumber;

  /// The oldest build number still supported; null asks nobody to update.
  final int? minSupportedBuild;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'published_at': publishedAt,
    'apk_url': apkUrl,
    if (sha256 != null) 'sha256': sha256,
    'assets': assets.map((a) => a.toJson()).toList(),
    if (buildNumber != null) 'build_number': buildNumber,
    if (minSupportedBuild != null) 'min_supported_build': minSupportedBuild,
  };

  @override
  bool operator ==(Object other) =>
      other is LatestBuildDto &&
      other.publishedAt == publishedAt &&
      other.apkUrl == apkUrl &&
      other.sha256 == sha256 &&
      other.buildNumber == buildNumber &&
      other.minSupportedBuild == minSupportedBuild &&
      _listEq(other.assets, assets) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    publishedAt,
    apkUrl,
    sha256,
    schemaVersion,
    buildNumber,
    minSupportedBuild,
    Object.hashAll(assets),
  );
}

/// The answer of `PUT /admin/app/min-build` (batch 147): the newest
/// release's build number and the oldest one still supported, either
/// null when unknown or unset.
final class AppUpdatePolicyDto {
  /// Creates the policy DTO.
  const AppUpdatePolicyDto({this.latestBuild, this.minSupportedBuild});

  /// Deserializes from a JSON map.
  factory AppUpdatePolicyDto.fromJson(Map<String, Object?> json) =>
      AppUpdatePolicyDto(
        latestBuild: json['latest_build'] as int?,
        minSupportedBuild: json['min_supported_build'] as int?,
      );

  /// The request body: make the newest release the minimum ([toLatest]),
  /// or clear it.
  static Map<String, Object?> request({required bool toLatest}) => {
    'to_latest': toLatest,
  };

  /// Reads `to_latest` from a request body; null when it is not a boolean.
  static bool? toLatestOf(Map<String, Object?> body) {
    final Object? value = body['to_latest'];
    return value is bool ? value : null;
  }

  /// The newest release's build number.
  final int? latestBuild;

  /// The oldest supported build number; null asks nobody to update.
  final int? minSupportedBuild;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'latest_build': latestBuild,
    'min_supported_build': minSupportedBuild,
  };

  @override
  bool operator ==(Object other) =>
      other is AppUpdatePolicyDto &&
      other.latestBuild == latestBuild &&
      other.minSupportedBuild == minSupportedBuild;

  @override
  int get hashCode => Object.hash(latestBuild, minSupportedBuild);
}

/// One per-ABI APK asset within a [LatestBuildDto].
final class BuildAssetDto {
  /// Creates a per-ABI asset descriptor.
  const BuildAssetDto({
    required this.abi,
    required this.url,
    required this.sha256,
  });

  /// Deserializes from a JSON map.
  factory BuildAssetDto.fromJson(Map<String, Object?> json) => BuildAssetDto(
    abi: json['abi']! as String,
    url: json['url']! as String,
    sha256: json['sha256']! as String,
  );

  /// The Android ABI this APK targets, e.g. `arm64-v8a`, `armeabi-v7a`,
  /// `x86_64`.
  final String abi;

  /// Direct download URL of this ABI's `.apk`.
  final String url;

  /// Lowercase hex SHA-256 of this ABI's `.apk`.
  final String sha256;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'abi': abi, 'url': url, 'sha256': sha256};

  @override
  bool operator ==(Object other) =>
      other is BuildAssetDto &&
      other.abi == abi &&
      other.url == url &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(abi, url, sha256);
}

bool _listEq(List<BuildAssetDto> a, List<BuildAssetDto> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
