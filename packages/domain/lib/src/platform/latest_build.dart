/// An immutable snapshot of the newest published Android build, sourced from
/// GitHub Releases (Platform update-check slice). Pure and total — carries
/// no framework or IO knowledge.
///
/// The repository publishes to a single rolling `latest` release tag (CI:
/// `publish_latest_apk`), so there is no meaningful semver to compare — the
/// client instead tracks [publishedAt] against the last release it already
/// showed the user (Infrastructure ADR — GithubBuildInfoRepository).
final class LatestBuild {
  /// Creates a latest-build snapshot.
  const LatestBuild({required this.publishedAt, required this.apkUrl});

  /// When this release was published, per the GitHub API.
  final DateTime publishedAt;

  /// Direct download URL of the release's `.apk` asset.
  final String apkUrl;

  @override
  bool operator ==(Object other) =>
      other is LatestBuild &&
      other.publishedAt == publishedAt &&
      other.apkUrl == apkUrl;

  @override
  int get hashCode => Object.hash(publishedAt, apkUrl);
}
