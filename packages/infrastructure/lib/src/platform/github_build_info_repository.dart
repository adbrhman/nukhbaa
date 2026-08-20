import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// GitHub Releases-backed implementation of [BuildInfoRepository].
///
/// Reads `GET /repos/{repoSlug}/releases/latest` and picks the first asset
/// whose name ends in `.apk`. The repository's release workflow
/// (`publish_latest_apk` in `build-verification.yml`) always publishes to a
/// single rolling `tag_name: latest` release, so `tag_name` carries no usable
/// version — [LatestBuild.publishedAt] (the release's `published_at`) is the
/// only reliable "is this newer" signal, and the client compares it against
/// the last release it already showed.
///
/// Results are cached in-process for [_cacheTtl] so a burst of app-open
/// checks (many devices, same minute) does not consume the unauthenticated
/// GitHub API rate limit (60 req/hour per source IP) — this server calls
/// GitHub, never the client (Coding Standards ADR — no HTTP in apps/mobile,
/// ADR-002 §2.8).
final class GithubBuildInfoRepository implements BuildInfoRepository {
  /// Creates the repository over an injected [http.Client] and the
  /// `owner/repo` slug to query.
  GithubBuildInfoRepository(
    this._httpClient, {
    this.repoSlug = 'adbrhman/nukhbaa',
  });

  final http.Client _httpClient;

  /// The `owner/repo` GitHub slug this repository queries.
  final String repoSlug;

  static const _cacheTtl = Duration(minutes: 5);
  LatestBuild? _cached;
  DateTime? _cachedAt;

  @override
  Future<Result<LatestBuild>> fetchLatest() async {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return Result.ok(cached);
    }

    final uri = Uri.https('api.github.com', '/repos/$repoSlug/releases/latest');

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: const {
              'User-Agent': 'nukhbaa-server',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return const Result.err(
          AppError.transient(
            'app.latest_build_unavailable',
            'تعذّر جلب أحدث إصدار حالياً.',
          ),
        );
      }

      final json = jsonDecode(response.body) as Map<String, Object?>;
      final rawPublishedAt = json['published_at'] as String?;
      final assets = json['assets'] as List<Object?>? ?? const [];

      String? apkUrl;
      for (final asset in assets) {
        final map = asset as Map<String, Object?>;
        final name = (map['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = map['browser_download_url'] as String?;
          break;
        }
      }

      final publishedAt = rawPublishedAt == null
          ? null
          : DateTime.tryParse(rawPublishedAt);

      if (publishedAt == null || apkUrl == null) {
        return const Result.err(
          AppError.transient(
            'app.latest_build_unavailable',
            'لا يتوفر ملف APK صالح في آخر إصدار منشور.',
          ),
        );
      }

      final build = LatestBuild(publishedAt: publishedAt, apkUrl: apkUrl);
      _cached = build;
      _cachedAt = DateTime.now();
      return Result.ok(build);
    } catch (e) {
      return Result.err(
        AppError.transient(
          'app.latest_build_unavailable',
          'تعذّر جلب أحدث إصدار حالياً.',
          e,
        ),
      );
    }
  }
}
