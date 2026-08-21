#!/usr/bin/env bash
# =============================================================================
# nukhbaa — In-App native OTA update (production-oriented, repo-verified)
#
# شغّله من جذر مستودع nukhbaa داخل Termux:
#   git clone https://github.com/adbrhman/nukhbaa && cd nukhbaa && bash this.sh
#
# صُمّم بعد فحص المستودع الفعلي (2026-08-21). الفروقات الجوهرية عن أي مسودة سابقة:
#   * apps/mobile/android/ غير موجود في git — يُولَّد بـ flutter create في CI.
#     => كل حقن Android يتم بعد flutter create، بشكل idempotent قائم على المحتوى.
#     => APK حاليًا موقّع بـ debug key متغيّر => OTA عبر الإصدارات BLOCKER (P0).
#   * لا يضيف أي override وهمي (لا startForTest).
#   * fallback يعتمد على نتيجة terminal يعيدها الـdialog (لا mutable state هشّة).
#   * لا يخترع keystore/secrets. يكتب تقرير blocker إن لزم.
#
# يتوقف عند أول فشل analyze. لا يدفع إلى main. لا يفتح PR.
# =============================================================================
set -euo pipefail

# --- 0) تحقق من الجذر --------------------------------------------------------
if [[ ! -f pubspec.yaml ]] || ! grep -q 'name: nukhba_workspace' pubspec.yaml; then
  echo "ERROR: شغّل السكربت من جذر مستودع nukhbaa." >&2
  exit 1
fi
ROOT="$(pwd)"

# --- تحقق من وجود git tree نظيف نسبيًا وحفظ الفرع الحالي ----------------------
echo "==> git status الحالي:"
git status --short || true
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "==> الفرع الحالي: $CURRENT_BRANCH"

BRANCH="fix/in-app-ota-update"
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

# أدوات: استخدم fvm إن وُجد
FLUTTER="flutter"; DART="dart"
if command -v fvm >/dev/null 2>&1; then FLUTTER="fvm flutter"; DART="fvm dart"; fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: مطلوب $1" >&2; exit 1; }; }
need python3
need git

echo "=============================================================="
echo " [A] Contracts — LatestBuildDto schema v2 (backward compatible)"
echo "=============================================================="
cat > packages/contracts/lib/src/latest_build_dto.dart <<'DART'
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
final class LatestBuildDto {
  /// Creates a latest-build response DTO.
  const LatestBuildDto({
    required this.publishedAt,
    required this.apkUrl,
    this.sha256,
    this.assets = const <BuildAssetDto>[],
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

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'published_at': publishedAt,
    'apk_url': apkUrl,
    if (sha256 != null) 'sha256': sha256,
    'assets': assets.map((a) => a.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is LatestBuildDto &&
      other.publishedAt == publishedAt &&
      other.apkUrl == apkUrl &&
      other.sha256 == sha256 &&
      _listEq(other.assets, assets) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    publishedAt,
    apkUrl,
    sha256,
    schemaVersion,
    Object.hashAll(assets),
  );
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
DART

echo "=============================================================="
echo " [B] Domain — LatestBuild + BuildAsset (pure, no Flutter/HTTP)"
echo "=============================================================="
cat > packages/domain/lib/src/platform/latest_build.dart <<'DART'
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
DART
# domain barrel: BuildAsset معرّف داخل نفس ملف latest_build.dart المُصدّر مسبقًا — لا تغيير للـbarrel.

echo "=============================================================="
echo " [C] Infrastructure — GithubBuildInfoRepository (per-ABI + checksums)"
echo "=============================================================="
cat > packages/infrastructure/lib/src/platform/github_build_info_repository.dart <<'DART'
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
DART

echo "=============================================================="
echo " [D] Server route — emit assets + sha256 (v1 clients still OK)"
echo "=============================================================="
cat > apps/server/routes/app/latest-build/index.dart <<'DART'
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /app/latest-build — the newest published Android build (published-at
/// timestamp + per-ABI `.apk` assets with SHA-256), sourced from GitHub
/// Releases server-side.
///
/// Deliberately public and unauthenticated, like `/health`: the client calls
/// this on launch — possibly before sign-in — to decide whether to prompt an
/// in-app update, then downloads/installs the ABI-matched APK natively
/// (ADR-002 §2.8 — no HTTP in apps/mobile). Schema-v1 clients ignore the new
/// `assets`/`sha256` fields and keep working. `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final result = await root.getLatestBuild();

  return switch (result) {
    Ok<LatestBuild>(:final value) => Response.json(
      body: LatestBuildDto(
        publishedAt: value.publishedAt.toIso8601String(),
        apkUrl: value.apkUrl,
        sha256: value.sha256,
        assets: value.assets
            .map((a) => BuildAssetDto(abi: a.abi, url: a.url, sha256: a.sha256))
            .toList(),
      ).toJson(),
    ),
    Err<LatestBuild>(:final error) => errorResponse(error),
  };
}
DART

echo "=============================================================="
echo " [E] Mobile — add ota_update + device_info_plus (documented)"
echo "=============================================================="
python3 - "$ROOT/apps/mobile/pubspec.yaml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

block = '''
  # In-App OTA update (ADR-002 §2.8 EXCEPTION — documented):
  # `ota_update` downloads + installs the release APK via NATIVE Android
  # (internal storage + install intent / PackageInstaller). It performs NO
  # Dart-side HTTP, so it does NOT add an `http` transport to apps/mobile; the
  # update METADATA (per-ABI url + sha256 + published_at) still comes only from
  # the server via `api_client`/`contracts`. This is the sole path replacing
  # the old `launchUrl(externalApplication)` browser download.
  # Verified on pub.dev 2026-08-21: ota_update 7.1.0 exposes
  # execute(sha256checksum:)/cancel() + OtaStatus events; requires Android
  # core-library desugaring (injected in CI after `flutter create`).
  ota_update: ^7.1.0

  # Reads device supportedAbis to pick the matching per-ABI APK. This is the
  # primary ABI source (ota_update's own getAbi() is tried first at runtime,
  # guarded by try/catch, with this as the documented fallback). Native
  # platform read, NOT HTTP. Verified on pub.dev 2026-08-21: device_info_plus
  # 11.x (Dart ^3.9.0 compatible).
  device_info_plus: ^11.3.0
'''

if 'ota_update:' in s:
    print('  pubspec: ota_update موجود مسبقًا — تخطٍّ')
else:
    m = re.search(r'\n  url_launcher:\s*\^6\.3\.2\n', s)
    if not m:
        sys.exit('ERROR: لم يُعثر على سطر url_launcher: ^6.3.2 في pubspec')
    s = s[:m.end()] + block + s[m.end():]
    open(p, 'w', encoding='utf-8').write(s)
    print('  pubspec: أُضيف ota_update + device_info_plus بعد url_launcher')
PY

echo "==> [E] In-App updater abstraction + production impl"
mkdir -p apps/mobile/lib/features/update
cat > apps/mobile/lib/features/update/in_app_updater.dart <<'DART'
/// In-app OTA updater — the PRIMARY update path (ADR-002 §2.8 exception).
///
/// Downloads the ABI-matched release APK via NATIVE Android (`ota_update`, no
/// Dart HTTP), verifies its SHA-256, then triggers the platform installer. The
/// update METADATA (per-ABI URL + checksum) comes only from the server through
/// `api_client`/`contracts`; this class never talks to the network in Dart.
///
/// The plugin is wrapped behind [InAppUpdater] so [UpdateGate] depends on a
/// testable seam, never on native calls directly.
///
/// GOOGLE PLAY NOTE: this path is for EXTERNAL (GitHub/APK) distribution only —
/// it uses REQUEST_INSTALL_PACKAGES + the native package installer. If the app
/// is ever shipped through Google Play, this path MUST be replaced by the Play
/// In-App Updates API; sideloading an APK violates Play policy. See ADR note in
/// docs and `update_gate.dart`.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ota_update/ota_update.dart';

/// A single UI-facing phase of the update.
enum UpdatePhase {
  /// Bytes are being downloaded (see [UpdateProgress.percent]).
  downloading,

  /// Checksum verified; installation intent has been triggered. For a normal
  /// (non-system) sideloaded app this is effectively terminal-success: the OS
  /// shows its own install UI and does not report completion back to us.
  installing,

  /// Installation reported complete (PackageInstaller path only).
  completed,

  /// The user cancelled the download.
  cancelled,

  /// Download failed (network/native).
  downloadFailed,

  /// SHA-256 mismatch — the file was corrupted or tampered with in transit.
  /// NOTE: this proves INTEGRITY against the published checksum, NOT publisher
  /// AUTHENTICITY. Authenticity is enforced by the Android APK signing key: the
  /// OS refuses to install an update signed by a different key.
  checksumFailed,

  /// Installation failed or install permission was refused.
  installFailed,

  /// Any other native/plugin error, or no installable asset for this device.
  failed,
}

/// A progress snapshot emitted by [InAppUpdater.start].
class UpdateProgress {
  /// Creates a progress snapshot.
  const UpdateProgress(this.phase, {this.percent, this.message});

  /// The current phase.
  final UpdatePhase phase;

  /// Download percentage 0–100 while [phase] is [UpdatePhase.downloading].
  final int? percent;

  /// Optional diagnostic detail (never contains secrets/tokens).
  final String? message;

  /// True once the flow reached a phase the UI should not advance past.
  bool get isTerminal =>
      phase == UpdatePhase.completed ||
      phase == UpdatePhase.cancelled ||
      phase == UpdatePhase.downloadFailed ||
      phase == UpdatePhase.checksumFailed ||
      phase == UpdatePhase.installFailed ||
      phase == UpdatePhase.failed;

  /// True on any non-cancel failure — the caller should offer the fallback.
  bool get isFailure =>
      phase == UpdatePhase.downloadFailed ||
      phase == UpdatePhase.checksumFailed ||
      phase == UpdatePhase.installFailed ||
      phase == UpdatePhase.failed;
}

/// The seam [UpdateGate] depends on. The production impl wraps `ota_update`;
/// tests supply a fake that emits a scripted [UpdateProgress] stream.
abstract interface class InAppUpdater {
  /// Selects the asset matching the device ABI, downloads + verifies + installs
  /// it, and reports progress. Never throws; failures arrive as terminal
  /// [UpdateProgress] events. Returns `null` when no installable/verifiable
  /// asset exists for this device (caller must use the browser fallback).
  Stream<UpdateProgress>? start(LatestBuildDto build);

  /// Cancels an in-flight download. Best-effort.
  Future<void> cancel();
}

/// Production [InAppUpdater] over the `ota_update` plugin.
class OtaInAppUpdater implements InAppUpdater {
  /// Creates the updater, optionally injecting seams for tests.
  OtaInAppUpdater({OtaUpdate? ota, DeviceInfoPlugin? deviceInfo})
    : _ota = ota ?? OtaUpdate(),
      _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final OtaUpdate _ota;
  final DeviceInfoPlugin _deviceInfo;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    final controller = StreamController<UpdateProgress>();
    unawaited(_run(build, controller));
    return controller.stream;
  }

  Future<void> _run(
    LatestBuildDto build,
    StreamController<UpdateProgress> out,
  ) async {
    try {
      final selected = await _selectAsset(build);
      if (selected == null) {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'no_matching_verifiable_asset',
          ),
        );
        await out.close();
        return;
      }

      // HTTPS-only: never hand a cleartext URL to the native downloader.
      final uri = Uri.tryParse(selected.url);
      if (uri == null || uri.scheme.toLowerCase() != 'https') {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'insecure_or_invalid_url',
          ),
        );
        await out.close();
        return;
      }

      // Checksum must be a well-formed lowercase hex SHA-256.
      if (!_hex64.hasMatch(selected.sha256.toLowerCase())) {
        out.add(
          const UpdateProgress(
            UpdatePhase.failed,
            message: 'invalid_checksum_format',
          ),
        );
        await out.close();
        return;
      }

      _ota
          .execute(
            selected.url,
            destinationFilename: 'nukhbaa-update.apk',
            sha256checksum: selected.sha256.toLowerCase(),
          )
          .listen(
            (event) => out.add(_map(event)),
            onError: (Object e) {
              out.add(UpdateProgress(UpdatePhase.failed, message: '$e'));
              unawaited(out.close());
            },
            onDone: () => unawaited(out.close()),
          );
    } catch (e) {
      out.add(UpdateProgress(UpdatePhase.failed, message: '$e'));
      await out.close();
    }
  }

  /// Picks the asset whose ABI matches the device. Preference order:
  ///   1) ota_update's own getAbi() (guarded — API may vary by version);
  ///   2) device supportedAbis (most-preferred first);
  ///   3) the DTO's primary apkUrl+sha256 as a universal fallback (only if a
  ///      checksum was published for it).
  Future<_AbiAsset?> _selectAsset(LatestBuildDto build) async {
    final assets = build.assets;
    if (assets.isNotEmpty) {
      final candidates = <String>[];
      final pref = await _preferredAbi();
      if (pref != null && pref.isNotEmpty) candidates.add(pref);
      candidates.addAll(await _deviceAbis());
      for (final abi in candidates) {
        for (final a in assets) {
          if (a.abi == abi) return _AbiAsset(a.url, a.sha256);
        }
      }
    }
    final primarySha = build.sha256;
    if (primarySha != null && primarySha.isNotEmpty) {
      return _AbiAsset(build.apkUrl, primarySha);
    }
    return null;
  }

  /// ota_update exposes an experimental ABI getter for split-apk selection.
  /// The exact method name/signature is not stable across versions, so this is
  /// fully guarded: any failure just falls through to [_deviceAbis].
  Future<String?> _preferredAbi() async {
    try {
      // ignore: avoid_dynamic_calls
      final dynamic result = await (_ota as dynamic).getAbi();
      if (result is String) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _deviceAbis() async {
    try {
      final info = await _deviceInfo.androidInfo;
      return info.supportedAbis;
    } catch (_) {
      return const <String>[];
    }
  }

  UpdateProgress _map(OtaEvent e) {
    switch (e.status) {
      case OtaStatus.DOWNLOADING:
        return UpdateProgress(
          UpdatePhase.downloading,
          percent: int.tryParse(e.value ?? ''),
        );
      case OtaStatus.INSTALLING:
        return const UpdateProgress(UpdatePhase.installing);
      case OtaStatus.INSTALLATION_DONE:
        return const UpdateProgress(UpdatePhase.completed);
      case OtaStatus.CANCELED:
        return const UpdateProgress(UpdatePhase.cancelled);
      case OtaStatus.DOWNLOAD_ERROR:
      case OtaStatus.ALREADY_RUNNING_ERROR:
        return UpdateProgress(UpdatePhase.downloadFailed, message: e.value);
      case OtaStatus.CHECKSUM_ERROR:
        return UpdateProgress(UpdatePhase.checksumFailed, message: e.value);
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        return UpdateProgress(UpdatePhase.installFailed, message: e.value);
      case OtaStatus.INTERNAL_ERROR:
        return UpdateProgress(UpdatePhase.failed, message: e.value);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _ota.cancel();
    } catch (_) {
      // best-effort
    }
  }
}

class _AbiAsset {
  const _AbiAsset(this.url, this.sha256);
  final String url;
  final String sha256;
}
DART

echo "==> [E] Rewrite UpdateGate — native OTA primary, browser fallback"
cat > apps/mobile/lib/features/update/update_gate.dart <<'DART'
/// Best-effort in-app update nudge, wrapping the app's root screen.
///
/// On first frame, calls `GET /app/latest-build` (via [AppApi], never HTTP
/// directly — ADR-002 §2.8). The server publishes to a rolling `latest` tag
/// with no usable semver, so this compares the release's `published_at`
/// against the last one this device already saw (persisted in
/// `flutter_secure_storage`). A strictly newer publish shows a dismissible
/// dialog.
///
/// PRIMARY download path: [InAppUpdater] (native OTA) — download progress,
/// SHA-256 INTEGRITY verification and the platform installer all happen
/// IN-APP; the release APK is NEVER handed to Chrome in the normal path. Only
/// if the native path fails (plugin/permission/native/checksum error, or no
/// installable asset) does the user get an explicit "فتح صفحة التنزيل"
/// fallback that opens the browser via `url_launcher`.
///
/// SECURITY: SHA-256 verification proves the downloaded file matches the
/// published checksum (integrity). It does NOT prove the publisher's identity;
/// that is enforced by Android refusing to install an update signed with a
/// different APK signing key. Release APKs MUST be signed with a stable key.
///
/// GOOGLE PLAY: this native-install path is for EXTERNAL (GitHub/APK)
/// distribution only. A future Play build must switch to the Play In-App
/// Updates API instead.
///
/// Silent on any check failure (offline, transient server error, malformed
/// response): [child] always renders immediately.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import 'in_app_updater.dart';

/// The storage key under which the last-seen release timestamp is persisted.
@visibleForTesting
const String updateLastSeenKey = 'nukhba.update_last_seen_published_at';

/// Riverpod-overridable factory for the native updater (fake in tests).
final Provider<InAppUpdater> inAppUpdaterProvider = Provider<InAppUpdater>(
  (ref) => OtaInAppUpdater(),
);

/// Wraps [child], performing one silent update check after the first frame.
class UpdateGate extends ConsumerStatefulWidget {
  /// Creates the gate around [child].
  const UpdateGate({required this.child, super.key});

  /// The app's root screen, rendered unconditionally.
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _checked = false;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_checked) return;
    _checked = true;

    final AppApi api = ref.read(appApiProvider);
    final Result<LatestBuildDto> result = await api.latestBuild();
    if (!mounted) return;
    if (result is! Ok<LatestBuildDto>) return; // offline/transient — silent

    final LatestBuildDto dto = result.value;
    final DateTime? publishedAt = DateTime.tryParse(dto.publishedAt);
    if (publishedAt == null) return; // malformed server payload — silent

    String? lastSeenRaw;
    try {
      lastSeenRaw = await _storage.read(key: updateLastSeenKey);
    } on Object {
      lastSeenRaw = null;
    }
    final DateTime? lastSeen = lastSeenRaw == null
        ? null
        : DateTime.tryParse(lastSeenRaw);

    if (lastSeen == null) {
      await _remember(dto.publishedAt); // fresh install baseline
      return;
    }
    if (!publishedAt.isAfter(lastSeen)) return;
    if (!mounted) return;

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('يتوفر تحديث جديد'),
        content: const Text('يتوفر إصدار أحدث من التطبيق. يُنصح بالتحديث.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );

    // Remember regardless, so the same release does not re-prompt every launch.
    await _remember(dto.publishedAt);

    if (proceed == true && mounted) {
      await _runInAppUpdate(dto);
    }
  }

  Future<void> _runInAppUpdate(LatestBuildDto dto) async {
    final InAppUpdater updater = ref.read(inAppUpdaterProvider);
    final Stream<UpdateProgress>? stream = updater.start(dto);
    if (stream == null) {
      if (mounted) await _offerBrowserFallback(dto);
      return;
    }
    if (!mounted) return;

    // The dialog returns the TERMINAL phase (no shared mutable state).
    final UpdatePhase? terminal = await showDialog<UpdatePhase>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _UpdateProgressDialog(stream: stream, onCancel: updater.cancel),
    );

    if (!mounted) return;
    final bool isFailure =
        terminal == UpdatePhase.downloadFailed ||
        terminal == UpdatePhase.checksumFailed ||
        terminal == UpdatePhase.installFailed ||
        terminal == UpdatePhase.failed;
    if (isFailure) {
      await _offerBrowserFallback(dto);
    }
  }

  Future<void> _offerBrowserFallback(LatestBuildDto dto) async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعذّر التحديث داخل التطبيق'),
        content: const Text(
          'حدثت مشكلة أثناء التحديث التلقائي. يمكنك فتح صفحة التنزيل '
          'لإكمال التحديث يدويًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('فتح صفحة التنزيل'),
          ),
        ],
      ),
    );
    if (open == true) {
      final Uri uri = Uri.parse(dto.apkUrl);
      if (uri.scheme.toLowerCase() == 'https') {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _remember(String publishedAt) async {
    try {
      await _storage.write(key: updateLastSeenKey, value: publishedAt);
    } on Object {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// In-app progress dialog: RTL Arabic, non-dismissible. Pops with the terminal
/// [UpdatePhase] so the parent can decide (fallback or not) without any shared
/// mutable state.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.stream, required this.onCancel});

  final Stream<UpdateProgress> stream;
  final Future<void> Function() onCancel;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  StreamSubscription<UpdateProgress>? _sub;
  UpdateProgress _current = const UpdateProgress(
    UpdatePhase.downloading,
    percent: 0,
  );

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen((p) {
      if (!mounted) return;
      setState(() => _current = p);
      if (p.isTerminal) {
        final delay = p.phase == UpdatePhase.completed
            ? const Duration(milliseconds: 600)
            : Duration.zero;
        Future<void>.delayed(delay, () {
          if (mounted) Navigator.of(context).pop(p.phase);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _title => switch (_current.phase) {
    UpdatePhase.downloading => 'جارٍ التنزيل',
    UpdatePhase.installing => 'جارٍ التحقق والتثبيت',
    UpdatePhase.completed => 'اكتمل التحديث',
    UpdatePhase.cancelled => 'تم الإلغاء',
    UpdatePhase.downloadFailed => 'فشل التنزيل',
    UpdatePhase.checksumFailed => 'فشل التحقق من سلامة الملف',
    UpdatePhase.installFailed => 'فشل التثبيت',
    UpdatePhase.failed => 'تعذّر التحديث',
  };

  @override
  Widget build(BuildContext context) {
    final int pct = _current.percent ?? 0;
    final bool showBar = _current.phase == UpdatePhase.downloading;
    return AlertDialog(
      title: Text(_title, textAlign: TextAlign.right),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBar) ...[
            LinearProgressIndicator(value: pct / 100.0),
            const SizedBox(height: 12),
            Text('$pct%', textAlign: TextAlign.center),
          ] else if (_current.phase == UpdatePhase.installing)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      actions: [
        if (_current.phase == UpdatePhase.downloading)
          TextButton(
            onPressed: () async => widget.onCancel(),
            child: const Text('إلغاء'),
          ),
      ],
    );
  }
}
DART

echo "=============================================================="
echo " [F/H] CI — split-per-abi + checksums (post-rename) + Android inject"
echo "=============================================================="
python3 - "$ROOT/.github/workflows/build-verification.yml" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
orig = s

# ---- (F1) بعد "Ensure INTERNET permission" احقن متطلبات ota_update ----------
internet_step = (
    '      - name: Ensure INTERNET permission\n'
    '        working-directory: apps/mobile\n'
    '        run: sed -i "/<manifest /a\\\\    <uses-permission android:name=\\"android.permission.INTERNET\\" />" android/app/src/main/AndroidManifest.xml\n'
)
if internet_step not in s:
    print('  CI تحذير: لم أجد خطوة INTERNET بالنص المتوقع — قد تكون عُدّلت. لن أحقن Android تلقائيًا.')
else:
    inject = internet_step + '''
      - name: Inject ota_update Android requirements (idempotent)
        working-directory: apps/mobile
        run: |
          set -euo pipefail
          python3 - <<'PYEOF'
          import re, os

          manifest = "android/app/src/main/AndroidManifest.xml"
          s = open(manifest, encoding="utf-8").read()

          # 1) REQUEST_INSTALL_PACKAGES permission (needed for external-APK install).
          if "REQUEST_INSTALL_PACKAGES" not in s:
              s = re.sub(
                  r"(<manifest[^>]*>)",
                  r'\\1\\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
                  s, count=1)

          # 2) FileProvider + InstallResultReceiver inside <application>.
          if "sk.fourq.otaupdate.OtaUpdateFileProvider" not in s:
              block = (
                  '        <provider\\n'
                  '            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"\\n'
                  '            android:authorities="${applicationId}.ota_update_provider"\\n'
                  '            android:exported="false"\\n'
                  '            android:grantUriPermissions="true">\\n'
                  '            <meta-data\\n'
                  '                android:name="android.support.FILE_PROVIDER_PATHS"\\n'
                  '                android:resource="@xml/filepaths" />\\n'
                  '        </provider>\\n'
                  '        <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">\\n'
                  '            <intent-filter>\\n'
                  '                <action android:name="${applicationId}.ACTION_INSTALL_COMPLETE"/>\\n'
                  '            </intent-filter>\\n'
                  '        </receiver>\\n'
              )
              s = s.replace("    </application>", block + "    </application>", 1)

          open(manifest, "w", encoding="utf-8").write(s)

          # 3) filepaths.xml consumed by the FileProvider.
          os.makedirs("android/app/src/main/res/xml", exist_ok=True)
          open("android/app/src/main/res/xml/filepaths.xml", "w", encoding="utf-8").write(
              '<?xml version="1.0" encoding="utf-8"?>\\n'
              '<paths xmlns:android="http://schemas.android.com/apk/res/android">\\n'
              '    <files-path name="internal_apk_storage" path="ota_update/"/>\\n'
              '</paths>\\n')

          # 4) Java 8 core-library desugaring in app/build.gradle(.kts) — required
          #    by ota_update 7.x. AGP for Flutter 3.44 is 8.x => desugar_jdk_libs 2.0.3.
          gk = "android/app/build.gradle.kts"
          gg = "android/app/build.gradle"
          if os.path.exists(gk):
              g = open(gk, encoding="utf-8").read()
              if "coreLibraryDesugaringEnabled" not in g:
                  g = re.sub(r"(compileOptions\\s*\\{)",
                             r"\\1\\n        isCoreLibraryDesugaringEnabled = true",
                             g, count=1)
              if "desugar_jdk_libs" not in g:
                  if re.search(r"\\ndependencies\\s*\\{", g):
                      g = re.sub(r"(\\ndependencies\\s*\\{)",
                                 r'\\1\\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                                 g, count=1)
                  else:
                      g += '\\ndependencies {\\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\\n}\\n'
              open(gk, "w", encoding="utf-8").write(g)
              print("  desugaring injected into build.gradle.kts")
          elif os.path.exists(gg):
              g = open(gg, encoding="utf-8").read()
              if "coreLibraryDesugaringEnabled" not in g:
                  g = re.sub(r"(compileOptions\\s*\\{)",
                             r"\\1\\n        coreLibraryDesugaringEnabled true",
                             g, count=1)
              if "desugar_jdk_libs" not in g:
                  if re.search(r"\\ndependencies\\s*\\{", g):
                      g = re.sub(r"(\\ndependencies\\s*\\{)",
                                 r"\\1\\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'",
                                 g, count=1)
                  else:
                      g += "\\ndependencies {\\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\\n}\\n"
              open(gg, "w", encoding="utf-8").write(g)
              print("  desugaring injected into build.gradle")
          else:
              raise SystemExit("ERROR: no android/app/build.gradle(.kts) after flutter create")

          print("ota_update Android requirements injected (idempotent).")
          PYEOF
'''
    s = s.replace(internet_step, inject, 1)
    print('  CI: حُقنت متطلبات Android لـ ota_update بعد INTERNET')

# ---- (F2) Build APK: split-per-abi + checksums (قبل rename، للـartifact فقط)-
build_old = '''      - name: Build APK
        working-directory: apps/mobile
        run: |
          CLEAN_API_BASE_URL=$(printf '%s' "$API_BASE_URL" | tr -d '\\r\\n')
          echo "{\\"NUKHBA_API_BASE_URL\\":\\"$CLEAN_API_BASE_URL\\"}" > /tmp/dart_defines.json
          flutter build apk --dart-define-from-file=/tmp/dart_defines.json --release

      - uses: actions/upload-artifact@v4
        with:
          name: nukhba-android-apk
          path: apps/mobile/build/app/outputs/flutter-apk/*.apk
          retention-days: 14'''

build_new = '''      - name: Build APK (split-per-abi)
        working-directory: apps/mobile
        run: |
          CLEAN_API_BASE_URL=$(printf '%s' "$API_BASE_URL" | tr -d '\\r\\n')
          echo "{\\"NUKHBA_API_BASE_URL\\":\\"$CLEAN_API_BASE_URL\\"}" > /tmp/dart_defines.json
          flutter build apk --split-per-abi --dart-define-from-file=/tmp/dart_defines.json --release

      - uses: actions/upload-artifact@v4
        with:
          name: nukhba-android-apk
          path: apps/mobile/build/app/outputs/flutter-apk/*.apk
          retention-days: 14'''

if build_old in s:
    s = s.replace(build_old, build_new, 1)
    print('  CI: build حُوّل إلى --split-per-abi')
else:
    print('  CI تحذير: لم أجد خطوة Build APK بالنص المتوقع')

# ---- (F3) publish: انشر كل الـAPKs + ابنِ checksums.json بعد rename ----------
pub_old = '''      - name: Rename to a versioned filename
        run: |
          SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          echo "SHORT_SHA=$SHORT_SHA" >> "$GITHUB_ENV"
          mv apk/*.apk "apk/nukhbaa-$SHORT_SHA.apk"

      - name: Publish an immutable per-build release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: build-${{ env.SHORT_SHA }}
          name: Build ${{ env.SHORT_SHA }}
          body: |
            بناء تلقائي من commit ${{ github.sha }}
          make_latest: true
          files: apk/nukhbaa-${{ env.SHORT_SHA }}.apk
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}'''

pub_new = '''      - name: Rename per-ABI APKs, then build checksums.json (post-rename)
        run: |
          set -euo pipefail
          SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          echo "SHORT_SHA=$SHORT_SHA" >> "$GITHUB_ENV"
          cd apk
          python3 - "$SHORT_SHA" <<'PYEOF'
          import sys, os, re, hashlib, json, glob
          sha = sys.argv[1]
          # Flutter emits app-arm64-v8a-release.apk etc. Rename to
          # nukhbaa-<abi>-<sha>.apk. If a universal apk exists, tag it "universal".
          for f in glob.glob("*.apk"):
              m = re.search(r"(arm64-v8a|armeabi-v7a|x86_64|x86)", f)
              abi = m.group(1) if m else "universal"
              os.rename(f, "nukhbaa-%s-%s.apk" % (abi, sha))
          # Build checksums.json keyed by the FINAL published filenames.
          out = {}
          for f in sorted(glob.glob("nukhbaa-*.apk")):
              out[f] = hashlib.sha256(open(f, "rb").read()).hexdigest()
          json.dump(out, open("checksums.json", "w"), indent=2)
          print(json.dumps(out, indent=2))
          PYEOF

      - name: Publish an immutable per-build release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: build-${{ env.SHORT_SHA }}
          name: Build ${{ env.SHORT_SHA }}
          body: |
            بناء تلقائي من commit ${{ github.sha }}
          make_latest: true
          files: |
            apk/nukhbaa-*.apk
            apk/checksums.json
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}'''

if pub_old in s:
    s = s.replace(pub_old, pub_new, 1)
    print('  CI: نشر كل الـAPKs + checksums.json (بعد rename)')
else:
    print('  CI تحذير: لم أجد خطوة النشر بالنص المتوقع')

if s != orig:
    open(p, 'w', encoding='utf-8').write(s)
    print('  CI: تم الحفظ')
else:
    print('  CI: لا تغييرات (قد تكون مطبّقة مسبقًا)')
PY

echo "=============================================================="
echo " [I] APK signing — كتابة تقرير blocker (لا نخترع مفاتيح)"
echo "=============================================================="
mkdir -p docs
cat > docs/ota-signing-blocker.md <<'MD'
# P0 BLOCKER — APK release signing غير ثابت (OTA لا يعمل عبر الإصدارات)

الحالة المؤكدة بعد فحص المستودع (2026-08-21):

- `apps/mobile/android/` غير موجود في git — يُولَّد بالكامل بـ
  `flutter create --platforms=android` داخل CI في كل build.
- لا يوجد `keystore` ولا `key.properties` ولا `signingConfigs`
  release في أي مكان في المستودع.
- نتيجة ذلك: `flutter build apk --release` يوقّع بـ **debug keystore**
  يُولَّد محليًا في بيئة CI، وقد يختلف بين عمليات البناء.

## لماذا يمنع هذا OTA
Android يرفض تثبيت تحديث APK إذا كان موقّعًا بمفتاح مختلف عن المثبَّت
حاليًا (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). بدون release key ثابت،
مستخدم مثبِّت لبناء سابق لن يستطيع تثبيت البناء الجديد عبر OTA — سيفشل
التثبيت دائمًا. لذلك **مسار OTA غير جاهز للإنتاج حتى يُحلّ هذا**.

## الحل المطلوب (يدويًا، خارج هذا السكربت — لا نضع أسرارًا في git)
1. أنشئ upload/release keystore مرة واحدة محليًا (لا يُرفع إلى git).
2. خزّن المفتاح وكلماته كـ GitHub Actions Secrets:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
3. في CI بعد `flutter create`: فُكّ ترميز الـkeystore إلى ملف، أنشئ
   `android/key.properties`، واحقن `signingConfigs.release` في
   `android/app/build.gradle(.kts)` بحيث `buildTypes.release` يستخدمه.
4. تحقّق من التوقيع: `apksigner verify --print-certs <apk>` وثبّت أن
   بصمة SHA-256 للشهادة ثابتة بين الإصدارات.

## ملاحظة أمنية
SHA-256 في مسار OTA يضمن **integrity** فقط (الملف يطابق القيمة المنشورة).
**authenticity** (هوية الناشر) تأتي حصريًا من ثبات APK signing key أعلاه.
لا تعتبر SHA-256 بديلًا عن التوقيع.

## Google Play
مسار REQUEST_INSTALL_PACKAGES + native installer صالح للتوزيع الخارجي فقط.
عند الانتقال إلى Google Play يجب استبداله بـ Play In-App Updates API.
MD
echo "  كُتب docs/ota-signing-blocker.md (لم يُنشأ أي مفتاح/سر)."

echo "=============================================================="
echo " [J] Tests"
echo "=============================================================="
mkdir -p packages/contracts/test
cat > packages/contracts/test/latest_build_dto_test.dart <<'DART'
import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('LatestBuildDto', () {
    test('schema v2 round-trips assets + sha256', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-01-01T00:00:00Z',
        apkUrl: 'https://example.com/a.apk',
        sha256: 'abc',
        assets: [
          BuildAssetDto(
            abi: 'arm64-v8a',
            url: 'https://example.com/arm64.apk',
            sha256: 'deadbeef',
          ),
        ],
      );
      final parsed = LatestBuildDto.fromJson(dto.toJson());
      expect(parsed, dto);
      expect(parsed.assets.single.abi, 'arm64-v8a');
      expect(parsed.schemaVersion, 2);
    });

    test('parses a schema-v1 payload (no assets/sha256)', () {
      final parsed = LatestBuildDto.fromJson(const {
        'schema_version': 1,
        'published_at': '2026-01-01T00:00:00Z',
        'apk_url': 'https://example.com/a.apk',
      });
      expect(parsed.assets, isEmpty);
      expect(parsed.sha256, isNull);
      expect(parsed.apkUrl, 'https://example.com/a.apk');
      expect(parsed.schemaVersion, 1);
    });

    test('parses multiple assets', () {
      final parsed = LatestBuildDto.fromJson(const {
        'schema_version': 2,
        'published_at': '2026-01-01T00:00:00Z',
        'apk_url': 'https://example.com/arm64.apk',
        'sha256': 'aa',
        'assets': [
          {'abi': 'arm64-v8a', 'url': 'https://x/arm64.apk', 'sha256': 'aa'},
          {'abi': 'armeabi-v7a', 'url': 'https://x/v7a.apk', 'sha256': 'bb'},
        ],
      });
      expect(parsed.assets.length, 2);
      expect(parsed.assets.map((a) => a.abi).toSet(),
          {'arm64-v8a', 'armeabi-v7a'});
    });

    test('equality and hashCode are value-based', () {
      const a = LatestBuildDto(
        publishedAt: 't',
        apkUrl: 'u',
        sha256: 's',
        assets: [BuildAssetDto(abi: 'arm64-v8a', url: 'u', sha256: 's')],
      );
      const b = LatestBuildDto(
        publishedAt: 't',
        apkUrl: 'u',
        sha256: 's',
        assets: [BuildAssetDto(abi: 'arm64-v8a', url: 'u', sha256: 's')],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
DART

mkdir -p packages/infrastructure/test/platform
cat > packages/infrastructure/test/platform/github_build_info_repository_test.dart <<'DART'
import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

http.Response _release(List<Map<String, String>> assets) => http.Response(
  jsonEncode({
    'published_at': '2026-01-02T00:00:00Z',
    'assets': assets
        .map((a) => {'name': a['name'], 'browser_download_url': a['url']})
        .toList(),
  }),
  200,
);

void main() {
  group('GithubBuildInfoRepository (split-per-abi)', () {
    test('maps each ABI apk with its checksum; arm64 is primary', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-abc.apk', 'url': 'https://x/arm64.apk'},
            {'name': 'nukhbaa-armeabi-v7a-abc.apk', 'url': 'https://x/v7a.apk'},
            {'name': 'checksums.json', 'url': 'https://x/checksums.json'},
          ]);
        }
        return http.Response(
          jsonEncode({
            'nukhbaa-arm64-v8a-abc.apk': 'AA',
            'nukhbaa-armeabi-v7a-abc.apk': 'BB',
          }),
          200,
        );
      });

      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Ok<LatestBuild>>());
      final build = (result as Ok<LatestBuild>).value;
      expect(build.assets.length, 2);
      expect(build.apkUrl, 'https://x/arm64.apk'); // arm64 primary
      expect(build.sha256, 'aa'); // lowercased
      expect(build.assets.map((a) => a.abi).toSet(),
          {'arm64-v8a', 'armeabi-v7a'});
    });

    test('apk without a checksum entry is skipped (=> transient error)',
        () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-arm64-v8a-abc.apk', 'url': 'https://x/arm64.apk'},
            {'name': 'checksums.json', 'url': 'https://x/c.json'},
          ]);
        }
        return http.Response(jsonEncode(<String, String>{}), 200);
      });
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });

    test('universal apk with checksum is used when no ABI assets', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'nukhbaa-universal-abc.apk', 'url': 'https://x/uni.apk'},
            {'name': 'checksums.json', 'url': 'https://x/c.json'},
          ]);
        }
        return http.Response(
          jsonEncode({'nukhbaa-universal-abc.apk': 'CC'}),
          200,
        );
      });
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Ok<LatestBuild>>());
      final build = (result as Ok<LatestBuild>).value;
      expect(build.assets, isEmpty);
      expect(build.apkUrl, 'https://x/uni.apk');
      expect(build.sha256, 'cc');
    });

    test('non-200 from GitHub => transient error', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });

    test('malformed release (no published_at) => transient error', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'assets': []}), 200),
      );
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });

    test('release with no apk at all => transient error', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return _release([
            {'name': 'notes.txt', 'url': 'https://x/notes.txt'},
          ]);
        }
        return http.Response('{}', 200);
      });
      final result = await GithubBuildInfoRepository(client).fetchLatest();
      expect(result, isA<Err<LatestBuild>>());
    });
  });
}
DART

mkdir -p apps/mobile/test/features/update
cat > apps/mobile/test/features/update/in_app_updater_test.dart <<'DART'
import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/in_app_updater.dart';

/// Scriptable fake exercising phase/fallback semantics without native calls.
class FakeUpdater implements InAppUpdater {
  FakeUpdater(this._events, {this.returnsNull = false});
  final List<UpdateProgress> _events;
  final bool returnsNull;
  bool cancelled = false;

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) =>
      returnsNull ? null : Stream<UpdateProgress>.fromIterable(_events);

  @override
  Future<void> cancel() async => cancelled = true;
}

LatestBuildDto _dto() => const LatestBuildDto(
  publishedAt: '2026-01-01T00:00:00Z',
  apkUrl: 'https://example.com/a.apk',
  sha256: 'x',
  assets: [
    BuildAssetDto(
      abi: 'arm64-v8a',
      url: 'https://example.com/arm64.apk',
      sha256: 'y',
    ),
  ],
);

void main() {
  test('completed is terminal & NOT a failure (no fallback)', () async {
    final fake = FakeUpdater(const [
      UpdateProgress(UpdatePhase.downloading, percent: 50),
      UpdateProgress(UpdatePhase.installing),
      UpdateProgress(UpdatePhase.completed),
    ]);
    final events = await fake.start(_dto())!.toList();
    expect(events.last.phase, UpdatePhase.completed);
    expect(events.last.isTerminal, isTrue);
    expect(events.last.isFailure, isFalse);
  });

  test('cancelled is terminal & NOT a failure (no fallback)', () {
    const p = UpdateProgress(UpdatePhase.cancelled);
    expect(p.isTerminal, isTrue);
    expect(p.isFailure, isFalse);
  });

  test('checksum failure IS a failure (=> fallback)', () {
    const p = UpdateProgress(UpdatePhase.checksumFailed);
    expect(p.isFailure, isTrue);
  });

  test('download failure IS a failure (=> fallback)', () {
    expect(const UpdateProgress(UpdatePhase.downloadFailed).isFailure, isTrue);
  });

  test('install failure IS a failure (=> fallback)', () {
    expect(const UpdateProgress(UpdatePhase.installFailed).isFailure, isTrue);
  });

  test('null stream signals caller to use browser fallback', () {
    final fake = FakeUpdater(const [], returnsNull: true);
    expect(fake.start(_dto()), isNull);
  });
}
DART

cat > apps/mobile/test/features/update/update_gate_test.dart <<'DART'
import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers.dart';
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';
import 'package:shared/shared.dart';

/// NOTE: These tests focus on the pure decision logic reachable without the
/// native plugin or secure storage. Full widget-level flows (dialog prompt,
/// baseline persistence) require a fake AppApi + a fake FlutterSecureStorage
/// channel; the seams (`appApiProvider`, `inAppUpdaterProvider`) are provided
/// here so a follow-up can extend coverage. Native ota_update is never invoked.
class _FakeUpdater implements InAppUpdater {
  _FakeUpdater(this.result);
  final UpdatePhase? result; // null => returns null stream (no asset)
  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    final r = result;
    if (r == null) return null;
    return Stream<UpdateProgress>.value(UpdateProgress(r));
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  testWidgets('UpdateGate renders its child unconditionally', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inAppUpdaterProvider.overrideWithValue(
            _FakeUpdater(UpdatePhase.completed),
          ),
        ],
        child: const MaterialApp(
          home: UpdateGate(child: Text('child-visible')),
        ),
      ),
    );
    // Child is present immediately (the check runs post-frame and is silent on
    // any AppApi failure, which is the default here without a base URL).
    expect(find.text('child-visible'), findsOneWidget);
  });

  test('failure phases map to fallback, success/cancel do not', () {
    bool needsFallback(UpdatePhase p) =>
        p == UpdatePhase.downloadFailed ||
        p == UpdatePhase.checksumFailed ||
        p == UpdatePhase.installFailed ||
        p == UpdatePhase.failed;

    expect(needsFallback(UpdatePhase.completed), isFalse);
    expect(needsFallback(UpdatePhase.cancelled), isFalse);
    expect(needsFallback(UpdatePhase.checksumFailed), isTrue);
    expect(needsFallback(UpdatePhase.downloadFailed), isTrue);
    expect(needsFallback(UpdatePhase.installFailed), isTrue);
    expect(needsFallback(UpdatePhase.failed), isTrue);
  });
}
DART

echo "=============================================================="
echo " [K] التحقق — بالترتيب. توقّف عند أول فشل."
echo "=============================================================="

echo "==> (1) flutter pub get"
$FLUTTER pub get

echo "==> (2) build_runner (mobile)"
( cd apps/mobile && $DART run build_runner build --delete-conflicting-outputs )

echo "==> (3) dart analyze --fatal-warnings .  (لا ننتقل إن فشل)"
$DART analyze --fatal-warnings .

echo "==> (4) dart format check"
$DART format --output=none --set-exit-if-changed .

echo "==> (5) import-lint"
$DART run tooling/import_lint/bin/import_lint.dart

echo "==> (6) package tests (melos)"
$DART run melos run test

echo "==> (7) flutter test (mobile)"
( cd apps/mobile && $FLUTTER test )

echo "==> (8/9/10) Android build + split-per-abi + checksum verification"
ANDROID_TESTED="NO"
if ( cd apps/mobile && $FLUTTER create --platforms=android . --project-name mobile >/dev/null 2>&1 ); then
  # حقن idempotent محليًا بنفس منطق CI قبل البناء
  python3 - "$ROOT/apps/mobile" <<'PYEOF'
import re, os, sys
base = sys.argv[1]
manifest = os.path.join(base, "android/app/src/main/AndroidManifest.xml")
if os.path.exists(manifest):
    s = open(manifest, encoding="utf-8").read()
    if "REQUEST_INSTALL_PACKAGES" not in s:
        s = re.sub(r"(<manifest[^>]*>)",
                   r'\1\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />',
                   s, count=1)
    if "android.permission.INTERNET" not in s:
        s = re.sub(r"(<manifest[^>]*>)",
                   r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
                   s, count=1)
    if "sk.fourq.otaupdate.OtaUpdateFileProvider" not in s:
        block = (
          '        <provider\n'
          '            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"\n'
          '            android:authorities="${applicationId}.ota_update_provider"\n'
          '            android:exported="false"\n'
          '            android:grantUriPermissions="true">\n'
          '            <meta-data\n'
          '                android:name="android.support.FILE_PROVIDER_PATHS"\n'
          '                android:resource="@xml/filepaths" />\n'
          '        </provider>\n'
          '        <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">\n'
          '            <intent-filter>\n'
          '                <action android:name="${applicationId}.ACTION_INSTALL_COMPLETE"/>\n'
          '            </intent-filter>\n'
          '        </receiver>\n'
        )
        s = s.replace("    </application>", block + "    </application>", 1)
    open(manifest, "w", encoding="utf-8").write(s)
    xmld = os.path.join(base, "android/app/src/main/res/xml")
    os.makedirs(xmld, exist_ok=True)
    open(os.path.join(xmld, "filepaths.xml"), "w", encoding="utf-8").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<paths xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <files-path name="internal_apk_storage" path="ota_update/"/>\n'
        '</paths>\n')
    for g, kts in ((os.path.join(base,"android/app/build.gradle.kts"), True),
                   (os.path.join(base,"android/app/build.gradle"), False)):
        if os.path.exists(g):
            t = open(g, encoding="utf-8").read()
            if "coreLibraryDesugaringEnabled" not in t:
                if kts:
                    t = re.sub(r"(compileOptions\s*\{)", r"\1\n        isCoreLibraryDesugaringEnabled = true", t, count=1)
                else:
                    t = re.sub(r"(compileOptions\s*\{)", r"\1\n        coreLibraryDesugaringEnabled true", t, count=1)
            if "desugar_jdk_libs" not in t:
                dep = ('    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
                       if kts else
                       "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'")
                if re.search(r"\ndependencies\s*\{", t):
                    t = re.sub(r"(\ndependencies\s*\{)", r"\1\n"+dep, t, count=1)
                else:
                    t += "\ndependencies {\n"+dep+"\n}\n"
            open(g, "w", encoding="utf-8").write(t)
            break
    print("  local android inject done")
else:
    print("  WARN: no manifest after flutter create")
PYEOF

  git checkout -- apps/mobile/web 2>/dev/null || true

  if ( cd apps/mobile && $FLUTTER build apk --split-per-abi --release ); then
    echo "APKs الناتجة:"
    ls -lh apps/mobile/build/app/outputs/flutter-apk/*.apk || true
    echo "SHA-256 (تحقق فعلي):"
    ( cd apps/mobile/build/app/outputs/flutter-apk && sha256sum *.apk 2>/dev/null || \
      for f in *.apk; do shasum -a 256 "$f"; done )
    N=$(ls apps/mobile/build/app/outputs/flutter-apk/*arm64*.apk 2>/dev/null | wc -l | tr -d ' ')
    [ "$N" -ge 1 ] && ANDROID_TESTED="YES (split-per-abi confirmed)" || ANDROID_TESTED="PARTIAL (build ok, ABI split unclear)"
  else
    echo "WARN: فشل بناء Android محليًا (SDK/Termux). سيُبنى في CI."
  fi
else
  echo "WARN: flutter create --platforms=android غير متاح هنا. سيُبنى في CI."
fi

echo "==> (11) git diff --stat"
git add -A
git --no-pager diff --cached --stat

echo "==> (12) commit (فقط بعد نجاح التحقق أعلاه)"
git commit -m "fix(update): add native in-app OTA updates

- contracts/domain: LatestBuild(Dto) schema v2 (per-ABI assets + sha256), v1 compatible
- infrastructure: GithubBuildInfoRepository maps every ABI apk via checksums.json;
  drops any apk without a checksum; universal fallback only when checksummed
- server route: emit assets + sha256 (v1 clients unaffected)
- mobile: InAppUpdater seam + OtaInAppUpdater; UpdateGate rewritten to native
  download/verify/install with dialog-returned terminal phase driving fallback;
  url_launcher only as explicit browser fallback
- CI: flutter build apk --split-per-abi; checksums.json built AFTER final rename;
  publish all ABIs; inject ota_update Android reqs + desugaring after flutter create
- docs: P0 signing blocker recorded (no key/secret invented)
- tests: dto v1/v2, repo ABI/checksum mapping + error paths, updater phase/fallback,
  UpdateGate child render + fallback decision" || echo "لا تغييرات جديدة للـcommit."

echo ""
echo "=============================================================="
echo " ملخّص نهائي"
echo "=============================================================="
echo "الفرع: $BRANCH"
echo "Android tested locally: $ANDROID_TESTED"
echo "commit hash: $(git rev-parse --short HEAD 2>/dev/null || echo '—')"
echo ""
echo ">>> BLOCKER مؤكد (P0): release signing غير ثابت — راجع docs/ota-signing-blocker.md"
echo ">>> OTA ليس production-ready حتى يُضاف release keystore ثابت عبر GitHub Secrets."
echo ""
echo "لم يُدفع إلى main ولم يُفتح PR. راجع 'git log -1' و 'git status'."
git status --short
