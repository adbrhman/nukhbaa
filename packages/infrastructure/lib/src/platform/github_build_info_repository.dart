import 'dart:convert';
import 'dart:io';

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
/// While the newest release has nothing verifiable yet -- CI publishes the
/// release first and uploads its APKs and `checksums.json` a minute later,
/// and the server is redeployed in that same minute -- the answer is the last
/// good one, else the newest recent release that does carry a verifiable APK
/// (problem Y7GU, 2026-10-03). Only when nothing verifiable exists anywhere
/// is it an error.
///
/// Results are cached in-process for [cacheTtl] so a burst of app-open checks
/// does not exhaust the unauthenticated GitHub rate limit. This SERVER calls
/// GitHub, never the client (ADR-002 §2.8 — no HTTP in apps/mobile).
///
/// Since batch 157 an APK's SHA-256 is read from the asset's own `digest`
/// in the release itself (GitHub computes it on upload), so a good answer
/// costs one GitHub call; `checksums.json` is downloaded only for an APK
/// without one. A failed answer is reused for [failureTtl]: Y7GU came back
/// on 2026-10-16 when every app open after a redeploy asked GitHub again
/// and failed, 69 times in minutes. A `token` (`NUKHBA_GITHUB_TOKEN`, any
/// GitHub token: the repository is public) raises the API limit from 60
/// calls an hour, shared by everything behind the host's address.
final class GithubBuildInfoRepository implements BuildInfoRepository {
  /// Creates the repository over an injected [http.Client] and the
  /// `owner/repo` slug to query.
  GithubBuildInfoRepository(
    this._httpClient, {
    this.repoSlug = 'adbrhman/nukhbaa',
    this.cacheTtl = const Duration(minutes: 5),
    this.failureTtl = const Duration(minutes: 2),
    String? token,
  }) : _apiHeaders = <String, String>{
         ..._githubHeaders,
         if (token != null && token.trim().isNotEmpty)
           'Authorization': 'Bearer ${token.trim()}',
       };

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

  /// How long a good answer is reused before GitHub is asked again.
  final Duration cacheTtl;

  /// How long a failed answer is reused before GitHub is asked again.
  final Duration failureTtl;

  /// The headers of the API calls: [_githubHeaders], with the token if any.
  final Map<String, String> _apiHeaders;

  /// An asset's `digest` as GitHub gives it: `sha256:` and 64 hex digits.
  static final RegExp _sha256Digest = RegExp(r'^sha256:([0-9a-fA-F]{64})$');

  /// How many recent releases are searched for a verifiable APK when the
  /// newest one has none yet.
  static const int _recentReleases = 5;

  static const Map<String, String> _githubHeaders = <String, String>{
    'User-Agent': 'nukhbaa-server',
    'Accept': 'application/vnd.github+json',
  };
  LatestBuild? _cached;
  DateTime? _cachedAt;
  Result<LatestBuild>? _failure;
  DateTime? _failedAt;

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
        DateTime.now().difference(cachedAt) < cacheTtl) {
      return Result.ok(cached);
    }
    final failure = _failure;
    final failedAt = _failedAt;
    if (failure != null &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < failureTtl) {
      return failure;
    }

    final Result<LatestBuild> latest = await _readRelease(
      Uri.https('api.github.com', '/repos/$repoSlug/releases/latest'),
    );
    if (latest is Ok<LatestBuild>) {
      return _remember(latest.value);
    }

    // The newest release can be published before its APKs and checksums are
    // uploaded, and GitHub can fail. The players keep the build they could
    // already get: the last good answer, else the newest recent release with
    // a verifiable APK.
    // Reused like a fresh answer, so the gap is not a burst of GitHub calls
    // against its unauthenticated rate limit.
    final LatestBuild? stale = _cached;
    if (stale != null) {
      return _remember(stale);
    }
    final LatestBuild? previous = await _newestVerifiableRelease();
    if (previous != null) {
      return _remember(previous);
    }
    if (latest case Err<LatestBuild>(:final error)) {
      stderr.writeln('[latest-build] ${error.message} ${error.cause ?? ''}');
    }
    _failure = latest;
    _failedAt = DateTime.now();
    return latest;
  }

  Result<LatestBuild> _remember(LatestBuild build) {
    _cached = build;
    _cachedAt = DateTime.now();
    _failure = null;
    _failedAt = null;
    return Result.ok(build);
  }

  /// The newest of the recent published releases that carries a verifiable
  /// APK, or null when none does or GitHub cannot be read.
  Future<LatestBuild?> _newestVerifiableRelease() async {
    try {
      final response = await _httpClient
          .get(
            Uri.https('api.github.com', '/repos/$repoSlug/releases', {
              'per_page': '$_recentReleases',
            }),
            headers: _apiHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      for (final Object? raw in decoded) {
        if (raw is! Map<String, Object?>) continue;
        if (raw['draft'] == true || raw['prerelease'] == true) continue;
        final Result<LatestBuild> built = await _buildFrom(raw);
        if (built is Ok<LatestBuild>) return built.value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads one release at [uri] and turns it into a [LatestBuild].
  Future<Result<LatestBuild>> _readRelease(Uri uri) async {
    try {
      final response = await _httpClient
          .get(uri, headers: _apiHeaders)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return Result.err(
          AppError.transient(
            _unavailable.code,
            _unavailable.message,
            'GitHub HTTP ${response.statusCode}',
          ),
        );
      }

      final Object? json = jsonDecode(response.body);
      if (json is! Map<String, Object?>) {
        return const Result.err(_unavailable);
      }
      return await _buildFrom(json);
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

  /// One release as a [LatestBuild]: its checksummed APKs, or an error when
  /// it has nothing verifiable.
  Future<Result<LatestBuild>> _buildFrom(Map<String, Object?> json) async {
    final rawPublishedAt = json['published_at'] as String?;
    final rawAssets = json['assets'] as List<Object?>? ?? const <Object?>[];

    final publishedAt = rawPublishedAt == null
        ? null
        : DateTime.tryParse(rawPublishedAt);
    if (publishedAt == null) {
      return const Result.err(_unavailable);
    }

    // Index assets by name -> download URL, keep each one's own digest,
    // and locate the checksum manifest.
    final byName = <String, String>{};
    final digests = <String, String>{};
    String? checksumsUrl;
    for (final raw in rawAssets) {
      if (raw is! Map<String, Object?>) continue;
      final name = (raw['name'] as String?) ?? '';
      final url = raw['browser_download_url'] as String?;
      if (url == null) continue;
      byName[name] = url;
      if (name.toLowerCase() == 'checksums.json') checksumsUrl = url;
      final Object? digest = raw['digest'];
      final Match? sha = digest is String
          ? _sha256Digest.firstMatch(digest.trim())
          : null;
      if (sha != null) digests[name] = sha.group(1)!.toLowerCase();
    }

    // The manifest is downloaded only when an APK has no digest of its own.
    final bool everyApkHasDigest = byName.keys
        .where((name) => name.toLowerCase().endsWith('.apk'))
        .every(digests.containsKey);
    final checksums = <String, String>{
      if (!everyApkHasDigest) ...await _fetchChecksums(checksumsUrl),
      ...digests,
    };

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
      return Result.err(
        AppError.transient(
          'app.latest_build_unavailable',
          'لا يتوفر ملف APK قابل للتحقق في آخر إصدار منشور.',
          '${byName.length} assets, ${checksums.length} checksums',
        ),
      );
    }

    return Result.ok(
      LatestBuild(
        publishedAt: publishedAt,
        apkUrl: apkUrl,
        sha256: apkSha,
        assets: assets,
        buildNumber: buildNumberOf(json['name']),
      ),
    );
  }

  /// The build number in a release's [name], `Build <sha> #<number>` since
  /// batch 147 (the CI run number), or null for an older release.
  static int? buildNumberOf(Object? name) {
    if (name is! String) return null;
    final Match? match = RegExp(r'#(\d+)\s*$').firstMatch(name.trim());
    final int? number = match == null ? null : int.tryParse(match.group(1)!);
    return number != null && number > 0 ? number : null;
  }

  Future<Map<String, String>> _fetchChecksums(String? url) async {
    if (url == null) return const <String, String>{};
    try {
      final res = await _httpClient
          .get(Uri.parse(url), headers: const {'User-Agent': 'nukhbaa-server'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        stderr.writeln('[latest-build] checksums.json: HTTP ${res.statusCode}');
        return const <String, String>{};
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, Object?>) return const <String, String>{};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (v is String) out[k] = v.toLowerCase();
      });
      return out;
    } catch (error) {
      stderr.writeln('[latest-build] checksums.json: $error');
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
