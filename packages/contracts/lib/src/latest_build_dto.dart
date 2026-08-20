/// The wire shape of a "latest published build" response
/// (`GET /app/latest-build`).
///
/// [schemaVersion] lets clients and archived payloads evolve safely
/// (API ADR, Section 4). There is deliberately no `version` field: the
/// server's release workflow publishes to a single rolling `latest` tag with
/// no usable semver, so [publishedAt] is the only "is this newer" signal
/// (see `GithubBuildInfoRepository`).
final class LatestBuildDto {
  /// Creates a latest-build response DTO.
  const LatestBuildDto({
    required this.publishedAt,
    required this.apkUrl,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory LatestBuildDto.fromJson(Map<String, Object?> json) {
    return LatestBuildDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      publishedAt: json['published_at']! as String,
      apkUrl: json['apk_url']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// ISO-8601 timestamp of when the release was published.
  final String publishedAt;

  /// Direct download URL of the release's `.apk` asset.
  final String apkUrl;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'published_at': publishedAt,
    'apk_url': apkUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is LatestBuildDto &&
      other.publishedAt == publishedAt &&
      other.apkUrl == apkUrl &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(publishedAt, apkUrl, schemaVersion);
}
