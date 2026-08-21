/// An immutable snapshot of the newest published Android build, sourced from
/// GitHub Releases (Platform update-check slice). Pure and total — carries
/// no framework or IO knowledge.
///
/// The repository publishes to a single rolling `latest` release tag (CI:
/// `publish_latest_apk`), so there is no meaningful semver to compare — the
/// client instead tracks [publishedAt] against the last release it already
/// showed the user (Infrastructure ADR — GithubBuildInfoRepository).
///
/// A build may ship one [BuildAsset] per Android ABI (`--split-per-abi`),
/// each with its own SHA-256. [apkUrl]/[sha256] carry the primary asset used
/// as a universal fallback when a device ABI has no dedicated asset.
final class LatestBuild {
  /// Creates a latest-build snapshot.
  const LatestBuild({
    required this.publishedAt,
    required this.apkUrl,
    this.sha256,
    this.assets = const <BuildAsset>[],
  });

  /// When this release was published, per the GitHub API.
  final DateTime publishedAt;

  /// Direct download URL of the primary `.apk` asset.
  final String apkUrl;

  /// Lowercase hex SHA-256 of [apkUrl]'s file, when published by CI.
  final String? sha256;

  /// Per-ABI assets. Empty when the release carries only a universal APK.
  final List<BuildAsset> assets;

  @override
  bool operator ==(Object other) =>
      other is LatestBuild &&
      other.publishedAt == publishedAt &&
      other.apkUrl == apkUrl &&
      other.sha256 == sha256 &&
      _listEq(other.assets, assets);

  @override
  int get hashCode =>
      Object.hash(publishedAt, apkUrl, sha256, Object.hashAll(assets));
}

/// One per-ABI APK asset of a [LatestBuild].
final class BuildAsset {
  /// Creates a per-ABI asset.
  const BuildAsset({
    required this.abi,
    required this.url,
    required this.sha256,
  });

  /// The Android ABI this APK targets (e.g. `arm64-v8a`).
  final String abi;

  /// Direct download URL of this ABI's `.apk`.
  final String url;

  /// Lowercase hex SHA-256 of this ABI's `.apk`.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is BuildAsset &&
      other.abi == abi &&
      other.url == url &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(abi, url, sha256);
}

bool _listEq(List<BuildAsset> a, List<BuildAsset> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
