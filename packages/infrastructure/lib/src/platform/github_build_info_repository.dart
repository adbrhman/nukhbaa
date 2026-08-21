import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// GitHub Releases-backed implementation of [BuildInfoRepository].
///
/// Reads `GET /repos/{repoSlug}/releases/latest`. The mobile client builds one
/// APK per ABI (`flutter build apk --split-per-abi`), so the release carries
/// several `*.apk` assets plus a machine-readable checksum manifest
/// `checksums.json` (published by CI, keyed by the exact published filenames).
/// This repository:
///   * parses `checksums.json` (name -> sha256) when present;
///   * maps every ABI-tagged `*.apk` asset to a [BuildAsset] with its SHA-256;
///   * exposes the arm64-v8a asset (else the first ABI asset, else a universal
///     `.apk` with a checksum) as the primary [LatestBuild.apkUrl] fallback.
///
/// Any `.apk` without a matching checksum entry is dropped: it is not
/// verifiable, so the client must never install it. If nothing verifiable
/// remains, this returns a transient error.
///
/// Results are cached in-process for [_cacheTtl] so a burst of app-open checks
/// does not exhaust the unauthenticated GitHub rate limit. This SERVER calls
/// GitHub, never the client (ADR-002 §2.8 — no HTTP in apps/mobile).
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

  /// The ABIs Flutter emits with `--split-per-abi`, matched in filenames.
  /// Order matters for `_abiFromFilename`: check `x86_64` before `x86`.
  static const List<String> _knownAbis = <String>[
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  static const _cacheTtl = Duration(minutes: 5);
  LatestBuild? _cached;
  DateTime? _cachedAt;

  static const _unavailable = AppError.transient(
    'app.latest_build_unavailable',
    'تعذّر جلب أحدث إصدار حالياً.',
  );

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
        return const Result.err(_unavailable);
      }

      final json = jsonDecode(response.body) as Map<String, Object?>;
      final rawPublishedAt = json['published_at'] as String?;
      final rawAssets = json['assets'] as List<Object?>? ?? const <Object?>[];

      final publishedAt = rawPublishedAt == null
          ? null
          : DateTime.tryParse(rawPublishedAt);
      if (publishedAt == null) {
        return const Result.err(_unavailable);
      }

      // Index assets by name -> download URL, and locate the checksum manifest.
      final byName = <String, String>{};
      String? checksumsUrl;
      for (final raw in rawAssets) {
        if (raw is! Map<String, Object?>) continue;
        final name = (raw['name'] as String?) ?? '';
        final url = raw['browser_download_url'] as String?;
        if (url == null) continue;
        byName[name] = url;
        if (name.toLowerCase() == 'checksums.json') checksumsUrl = url;
      }

      final checksums = await _fetchChecksums(checksumsUrl);

      // One BuildAsset per ABI-tagged, checksummed apk.
      final assets = <BuildAsset>[];
      for (final entry in byName.entries) {
        final name = entry.key;
        if (!name.toLowerCase().endsWith('.apk')) continue;
        final abi = _abiFromFilename(name);
        if (abi == null) continue; // universal apk handled in the fallback path
        final sha = checksums[name];
        if (sha == null) continue; // no checksum => not verifiable, skip
        assets.add(BuildAsset(abi: abi, url: entry.value, sha256: sha));
      }

      // Primary fallback: arm64-v8a if present, else first ABI asset.
      BuildAsset? primary;
      for (final a in assets) {
        if (a.abi == 'arm64-v8a') {
          primary = a;
          break;
        }
      }
      primary ??= assets.isNotEmpty ? assets.first : null;

      String? apkUrl = primary?.url;
      String? apkSha = primary?.sha256;

      if (apkUrl == null) {
        // No ABI assets: fall back to a universal `.apk` that HAS a checksum.
        for (final entry in byName.entries) {
          final name = entry.key;
          if (!name.toLowerCase().endsWith('.apk')) continue;
          final sha = checksums[name];
          if (sha == null) continue;
          apkUrl = entry.value;
          apkSha = sha;
          break;
        }
      }

      if (apkUrl == null) {
        return const Result.err(
          AppError.transient(
            'app.latest_build_unavailable',
            'لا يتوفر ملف APK قابل للتحقق في آخر إصدار منشور.',
          ),
        );
      }

      final build = LatestBuild(
        publishedAt: publishedAt,
        apkUrl: apkUrl,
        sha256: apkSha,
        assets: assets,
      );
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

  Future<Map<String, String>> _fetchChecksums(String? url) async {
    if (url == null) return const <String, String>{};
    try {
      final res = await _httpClient
          .get(Uri.parse(url), headers: const {'User-Agent': 'nukhbaa-server'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const <String, String>{};
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, Object?>) return const <String, String>{};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (v is String) out[k] = v.toLowerCase();
      });
      return out;
    } catch (_) {
      return const <String, String>{};
    }
  }

  static String? _abiFromFilename(String name) {
    final lower = name.toLowerCase();
    for (final abi in _knownAbis) {
      if (lower.contains(abi)) return abi;
    }
    return null;
  }
}
