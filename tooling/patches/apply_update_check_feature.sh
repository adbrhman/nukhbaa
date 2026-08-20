#!/usr/bin/env bash
# تشغيل من جذر المستودع (المجلد الذي يحوي apps/ و packages/):
#   bash tooling/patches/apply_update_check_feature.sh
#
# يضيف ميزة "فحص التحديث داخل التطبيق" عبر مسار سيرفر جديد
# GET /app/latest-build (يقرأ GitHub Releases نيابة عن العميل — ADR-002 §2.8:
# لا HTTP في apps/mobile)، ويقارن العميل `published_at` مع آخر إصدار رآه
# (مخزَّن في flutter_secure_storage — بلا تبعية جديدة سوى url_launcher
# لفتح رابط الـ APK في المتصفح).
#
# آمن لإعادة التشغيل: كل خطوة تتحقق أولاً هل التغيير مطبَّق مسبقاً وتتخطاه.
set -euo pipefail

if [[ ! -f "melos.yaml" && ! -f "pubspec.yaml" ]]; then
  echo "خطأ: شغّل هذا السكربت من جذر المستودع (نفس مستوى apps/ و packages/)." >&2
  exit 1
fi

FAIL=0

mkdir -p apps/server/routes/app/latest-build
mkdir -p apps/server/test/routes/app
mkdir -p apps/mobile/lib/features/update
mkdir -p packages/domain/lib/src/platform
mkdir -p packages/application/lib/src/platform/ports
mkdir -p packages/infrastructure/lib/src/platform
mkdir -p packages/infrastructure/test/platform
mkdir -p packages/contracts/lib/src
mkdir -p packages/api_client/lib/src

# ---------------------------------------------------------------------------
# 1) ملفات جديدة (كتابة كاملة — آمنة للتكرار لأنها deterministic)
# ---------------------------------------------------------------------------

cat > packages/domain/lib/src/platform/latest_build.dart << 'EOF'
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
EOF

cat > packages/application/lib/src/platform/ports/build_info_repository.dart << 'EOF'
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for discovering the newest published Android build (Repository
/// pattern — Application ADR, Section 9). Implemented in Infrastructure over
/// GitHub Releases; the application depends on this interface, never on a
/// concrete HTTP client.
abstract interface class BuildInfoRepository {
  /// Returns `Ok(LatestBuild)` for the newest published release, or
  /// `Err(transient)` if the source could not be reached or carried no
  /// `.apk` asset.
  Future<Result<LatestBuild>> fetchLatest();
}
EOF

cat > packages/application/lib/src/platform/get_latest_build.dart << 'EOF'
import 'package:application/src/platform/ports/build_info_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: report the newest published Android build so the client can
/// prompt an in-app update (Platform update-check slice).
final class GetLatestBuild {
  /// Creates the use-case with its required [BuildInfoRepository] port.
  const GetLatestBuild(this._buildInfoRepository);

  final BuildInfoRepository _buildInfoRepository;

  /// Executes the check. Never throws; returns a typed [Result].
  Future<Result<LatestBuild>> call() => _buildInfoRepository.fetchLatest();
}
EOF

cat > packages/infrastructure/lib/src/platform/github_build_info_repository.dart << 'EOF'
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

    final uri = Uri.https(
      'api.github.com',
      '/repos/$repoSlug/releases/latest',
    );

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
EOF

cat > packages/contracts/lib/src/latest_build_dto.dart << 'EOF'
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
EOF

cat > apps/server/routes/app/latest-build/index.dart << 'EOF'
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /app/latest-build — the newest published Android build (published-at
/// timestamp + direct `.apk` download URL), sourced from GitHub Releases
/// server-side.
///
/// Deliberately public and unauthenticated, like `/health`: the client calls
/// this on launch — possibly before sign-in — to decide whether to prompt an
/// in-app update. No principal, no business data; this route only proxies a
/// read the client is forbidden to make itself (Coding Standards ADR — no
/// HTTP in apps/mobile, ADR-002 §2.8). `405` on any non-GET method.
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
      ).toJson(),
    ),
    Err<LatestBuild>(:final error) => errorResponse(error),
  };
}
EOF

cat > apps/server/test/routes/app/latest_build_test.dart << 'EOF'
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes live outside `lib/`, so they have no `package:` URI; a
// relative import is the only way to unit-test the handler in isolation
// (mirrors `test/routes/health_test.dart`).
// ignore: always_use_package_imports
import '../../../routes/app/latest-build/index.dart' as route;

/// In-memory fake of the build-info port (Coding Standards ADR, Section 6).
final class _FakeBuildInfoRepository implements BuildInfoRepository {
  _FakeBuildInfoRepository(this._response);

  final Result<LatestBuild> _response;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => _response;
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

({_MockRequestContext context, Future<CompositionRoot> root}) _wire({
  required Result<LatestBuild> response,
  HttpMethod method = HttpMethod.get,
}) {
  final useCase = GetLatestBuild(_FakeBuildInfoRepository(response));
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(getLatestBuild: useCase),
  );

  final request = _MockRequest();
  when(() => request.method).thenReturn(method);

  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);

  return (context: context, root: root);
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded.cast<String, Object?>();
}

void main() {
  group('GET /app/latest-build route', () {
    test('returns 200 with the latest version and apk url', () async {
      final publishedAt = DateTime.utc(2026, 8, 20, 12);
      final wired = _wire(
        response: Result.ok(
          LatestBuild(
            publishedAt: publishedAt,
            apkUrl: 'https://example.com/a.apk',
          ),
        ),
      );

      final response = await route.onRequest(wired.context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await _decodeBody(response);
      expect(body['published_at'], publishedAt.toIso8601String());
      expect(body['apk_url'], 'https://example.com/a.apk');
      expect(body['schema_version'], 1);
    });

    test('surfaces a transient error as 503', () async {
      final wired = _wire(
        response: const Result.err(
          AppError.transient(
            'app.latest_build_unavailable',
            'تعذّر جلب أحدث إصدار حالياً.',
          ),
        ),
      );

      final response = await route.onRequest(wired.context);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });

    test(
      'rejects non-GET methods with 405 without touching the use-case',
      () async {
        final wired = _wire(
          response: Result.ok(
            LatestBuild(
              publishedAt: DateTime.utc(2026, 8, 20),
              apkUrl: 'https://example.com/a.apk',
            ),
          ),
          method: HttpMethod.post,
        );

        final response = await route.onRequest(wired.context);

        expect(response.statusCode, HttpStatus.methodNotAllowed);
        verifyNever(() => wired.context.read<Future<CompositionRoot>>());
      },
    );
  });
}
EOF

cat > packages/application/test/get_latest_build_test.dart << 'EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// In-memory fake of the port (Coding Standards ADR, Section 6: use-cases are
/// tested against in-memory fakes, no infrastructure).
final class _FakeBuildInfoRepository implements BuildInfoRepository {
  _FakeBuildInfoRepository(this._response);
  final Result<LatestBuild> _response;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => _response;
}

void main() {
  group('GetLatestBuild', () {
    test('passes through a successful repository read', () async {
      final build = LatestBuild(
        publishedAt: DateTime.utc(2026, 8, 20),
        apkUrl: 'https://example.com/a.apk',
      );
      final useCase = GetLatestBuild(
        _FakeBuildInfoRepository(Result.ok(build)),
      );

      final result = await useCase();

      expect(result.isOk, isTrue);
      expect((result as Ok<LatestBuild>).value, build);
    });

    test('passes through a transient repository failure', () async {
      final useCase = GetLatestBuild(
        _FakeBuildInfoRepository(
          const Result.err(
            AppError.transient('app.latest_build_unavailable', 'unreachable'),
          ),
        ),
      );

      final result = await useCase();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });
  });
}
EOF

cat > packages/infrastructure/test/platform/github_build_info_repository_test.dart << 'EOF'
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

String _releaseBody({
  String publishedAt = '2026-08-20T12:00:00Z',
  bool includeApk = true,
}) => jsonEncode({
  'tag_name': 'latest',
  'published_at': publishedAt,
  'assets': [
    if (includeApk)
      {
        'name': 'nukhbaa.apk',
        'browser_download_url': 'https://example.com/nukhbaa.apk',
      },
    {
      'name': 'source.zip',
      'browser_download_url': 'https://example.com/source.zip',
    },
  ],
});

void main() {
  group('GithubBuildInfoRepository.fetchLatest', () {
    test('maps a 200 response to LatestBuild (published_at + apk url)',
        () async {
      final repo = GithubBuildInfoRepository(
        MockClient((_) async => http.Response(_releaseBody(), 200)),
      );

      final result = await repo.fetchLatest();

      expect(result.isOk, isTrue);
      final build = (result as Ok<LatestBuild>).value;
      expect(build.publishedAt, DateTime.parse('2026-08-20T12:00:00Z'));
      expect(build.apkUrl, 'https://example.com/nukhbaa.apk');
    });

    test('caches a successful read within the TTL (one network call)',
        () async {
      var calls = 0;
      final repo = GithubBuildInfoRepository(
        MockClient((_) async {
          calls++;
          return http.Response(_releaseBody(), 200);
        }),
      );

      await repo.fetchLatest();
      await repo.fetchLatest();

      expect(calls, 1);
    });

    test('returns a transient error on a non-200 response', () async {
      final repo = GithubBuildInfoRepository(
        MockClient((_) async => http.Response('not found', 404)),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });

    test('returns a transient error when no .apk asset is published',
        () async {
      final repo = GithubBuildInfoRepository(
        MockClient(
          (_) async => http.Response(_releaseBody(includeApk: false), 200),
        ),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });

    test('returns a transient error on a network failure', () async {
      final repo = GithubBuildInfoRepository(
        MockClient((_) async => throw Exception('boom')),
      );

      final result = await repo.fetchLatest();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });
  });
}
EOF

cat > packages/contracts/test/latest_build_dto_test.dart << 'EOF'
import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('LatestBuildDto', () {
    test('round-trips through JSON', () {
      const dto = LatestBuildDto(
        publishedAt: '2026-08-20T12:00:00.000Z',
        apkUrl: 'https://example.com/a.apk',
      );
      final decoded = LatestBuildDto.fromJson(dto.toJson());
      expect(decoded, dto);
      expect(decoded.schemaVersion, LatestBuildDto.currentSchemaVersion);
    });

    test('defaults schema_version to 1 when absent (back-compat)', () {
      final decoded = LatestBuildDto.fromJson(const {
        'published_at': '2026-08-20T12:00:00.000Z',
        'apk_url': 'https://example.com/a.apk',
      });
      expect(decoded.schemaVersion, 1);
      expect(decoded.publishedAt, '2026-08-20T12:00:00.000Z');
    });
  });
}
EOF

cat > packages/api_client/lib/src/app_api.dart << 'EOF'
import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the platform "App" surface of `apps/server`.
///
/// Wraps the one ratified route:
///   * `GET /app/latest-build` -> [LatestBuildDto] (newest published Android
///     build, sourced from GitHub Releases server-side —
///     `routes/app/latest-build/index.dart`).
///
/// Deliberately unauthenticated: the app calls this on launch, possibly
/// before sign-in, to decide whether to prompt an in-app update. A pure
/// read, no side effect; returns a typed [Result] and never throws.
final class AppApi {
  /// Creates the App client over the shared [ApiTransport].
  const AppApi(this._transport);

  final ApiTransport _transport;

  /// `GET /app/latest-build` — the newest published Android build.
  Future<Result<LatestBuildDto>> latestBuild() {
    return _transport.getObject<LatestBuildDto>(
      '/app/latest-build',
      parse: LatestBuildDto.fromJson,
    );
  }
}
EOF

cat > packages/api_client/test/app_api_test.dart << 'EOF'
import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/mock_transport.dart';

void main() {
  group('AppApi.latestBuild (GET /app/latest-build)', () {
    test('200 -> Ok(LatestBuildDto)', () async {
      const dto = LatestBuildDto(
        publishedAt: '2026-08-20T12:00:00.000Z',
        apkUrl: 'https://example.com/a.apk',
      );
      final ctx = buildTransport((_) async => okJson(dto.toJson()));

      final result = await AppApi(ctx.transport).latestBuild();

      expect(result, const Result<LatestBuildDto>.ok(dto));
      final req = ctx.captured.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/app/latest-build');
    });

    test('503 -> Err(transient)', () async {
      final ctx = buildTransport(
        (_) async => errorEnvelope(
          503,
          'app.latest_build_unavailable',
          'unreachable',
        ),
      );

      final result = await AppApi(ctx.transport).latestBuild();

      expect(result.isErr, isTrue);
      expect(
        (result as Err<LatestBuildDto>).error.kind,
        ErrorKind.transient,
      );
    });
  });
}
EOF

cat > apps/mobile/lib/features/update/update_gate.dart << 'EOF'
/// Best-effort in-app update nudge, wrapping the app's root screen.
///
/// On first frame, calls `GET /app/latest-build` (via [AppApi], never HTTP
/// directly — ADR-002 §2.8). The server's release workflow publishes to a
/// single rolling `latest` tag with no usable semver, so there is no
/// "current app version" to compare against — instead this compares the
/// release's `published_at` against the last one this device already saw
/// (persisted in `flutter_secure_storage`, the same mechanism already used
/// by [SecureTokenStore] — no new dependency). A strictly newer publish
/// triggers a dismissible dialog offering to open the `.apk` download in the
/// system browser via `url_launcher`.
///
/// Silent on any failure (offline, transient server error, malformed
/// response, storage read failure): this is a nudge, never a gate on app
/// usage — [child] always renders immediately.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';

/// The storage key under which the last-seen release timestamp is
/// persisted (ISO-8601 string).
@visibleForTesting
const String updateLastSeenKey = 'nukhba.update_last_seen_published_at';

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
      lastSeenRaw = null; // treat a storage read failure as "never seen"
    }
    final DateTime? lastSeen = lastSeenRaw == null
        ? null
        : DateTime.tryParse(lastSeenRaw);

    // First-ever check on this device: establish the baseline silently
    // (a fresh install is already running roughly this release) instead of
    // nagging immediately after first launch.
    if (lastSeen == null) {
      await _remember(dto.publishedAt);
      return;
    }

    if (!publishedAt.isAfter(lastSeen)) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('يتوفر تحديث جديد'),
        content: const Text('يتوفر إصدار أحدث من التطبيق. يُنصح بالتحديث.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await launchUrl(
                Uri.parse(dto.apkUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );

    // Remember this release regardless of the user's choice, so the same
    // release does not re-prompt on every subsequent launch.
    await _remember(dto.publishedAt);
  }

  Future<void> _remember(String publishedAt) async {
    try {
      await _storage.write(key: updateLastSeenKey, value: publishedAt);
    } on Object {
      // Best-effort only — a failed write just means this release may
      // prompt again next launch, which is safe.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
EOF

echo "== الملفات الجديدة: تم =="

# ---------------------------------------------------------------------------
# 2) تعديلات على ملفات موجودة (استبدالات دقيقة idempotent)
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import sys

# (path, old, new, label)
EDITS = [
("packages/domain/lib/domain.dart",
 "export 'src/platform/health.dart';",
 "export 'src/platform/health.dart';\nexport 'src/platform/latest_build.dart';",
 "domain.dart: تصدير LatestBuild"),

("packages/application/lib/application.dart",
 "export 'src/platform/check_health.dart';\nexport 'src/platform/ports/health_repository.dart';",
 "export 'src/platform/check_health.dart';\nexport 'src/platform/get_latest_build.dart';\nexport 'src/platform/ports/build_info_repository.dart';\nexport 'src/platform/ports/health_repository.dart';",
 "application.dart: تصدير GetLatestBuild + BuildInfoRepository"),

("packages/infrastructure/lib/infrastructure.dart",
 "export 'src/platform/postgres_health_repository.dart';",
 "export 'src/platform/github_build_info_repository.dart';\nexport 'src/platform/postgres_health_repository.dart';",
 "infrastructure.dart: تصدير GithubBuildInfoRepository"),

("packages/contracts/lib/contracts.dart",
 "export 'src/health_dto.dart';",
 "export 'src/health_dto.dart';\nexport 'src/latest_build_dto.dart';",
 "contracts.dart: تصدير LatestBuildDto"),

("packages/api_client/lib/api_client.dart",
 "export 'src/api_transport.dart' show ApiTransport, TokenProvider;\nexport 'src/auth_api.dart' show AuthApi;",
 "export 'src/api_transport.dart' show ApiTransport, TokenProvider;\nexport 'src/app_api.dart' show AppApi;\nexport 'src/auth_api.dart' show AuthApi;",
 "api_client.dart: تصدير AppApi"),

# --- composition_root.dart: 7 تعديلات دقيقة ---
("apps/server/lib/composition/composition_root.dart",
 "    required this.checkHealth,\n    required this.authenticateRequest,",
 "    required this.checkHealth,\n    required this.getLatestBuild,\n    required this.authenticateRequest,",
 "composition_root.dart 1/7: حقل مطلوب في الكونستركتور الإنتاجي"),

("apps/server/lib/composition/composition_root.dart",
 "    CheckHealth? checkHealth,\n    LoginWithPassword? login,",
 "    CheckHealth? checkHealth,\n    GetLatestBuild? getLatestBuild,\n    LoginWithPassword? login,",
 "composition_root.dart 2/7: param اختياري في forTesting"),

("apps/server/lib/composition/composition_root.dart",
 "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),\n       login = login ?? _absentLogin(),",
 "  }) : checkHealth = checkHealth ?? _absentCheckHealth(),\n       getLatestBuild = getLatestBuild ?? _absentGetLatestBuild(),\n       login = login ?? _absentLogin(),",
 "composition_root.dart 3/7: تهيئة absent في forTesting"),

("apps/server/lib/composition/composition_root.dart",
 "  /// The health use-case, ready to be invoked by routes.\n  final CheckHealth checkHealth;",
 "  /// The health use-case, ready to be invoked by routes.\n  final CheckHealth checkHealth;\n\n  /// Reports the newest published Android build, ready to be invoked by\n  /// routes.\n  final GetLatestBuild getLatestBuild;",
 "composition_root.dart 4/7: تصريح الحقل"),

("apps/server/lib/composition/composition_root.dart",
 "  static CheckHealth _absentCheckHealth() =>\n      CheckHealth(_UnwiredHealthRepository());",
 "  static CheckHealth _absentCheckHealth() =>\n      CheckHealth(_UnwiredHealthRepository());\n\n  /// Backs an \"absent\" [GetLatestBuild] in [CompositionRoot.forTesting]:\n  /// throws if a test reaches the update-check slice it never wired.\n  static GetLatestBuild _absentGetLatestBuild() =>\n      GetLatestBuild(_UnwiredBuildInfoRepository());",
 "composition_root.dart 5/7: مولّد absent"),

("apps/server/lib/composition/composition_root.dart",
 "final class _UnwiredHealthRepository implements HealthRepository {\n  @override\n  Future<Result<bool>> pingDatabase() =>\n      throw StateError('CheckHealth was not wired into this test root');\n}",
 "final class _UnwiredHealthRepository implements HealthRepository {\n  @override\n  Future<Result<bool>> pingDatabase() =>\n      throw StateError('CheckHealth was not wired into this test root');\n}\n\n/// Backs an \"absent\" [GetLatestBuild] in [CompositionRoot.forTesting]: throws\n/// if a test reaches the update-check slice it never wired.\nfinal class _UnwiredBuildInfoRepository implements BuildInfoRepository {\n  @override\n  Future<Result<LatestBuild>> fetchLatest() =>\n      throw StateError('GetLatestBuild was not wired into this test root');\n}",
 "composition_root.dart 5b/7: صنف _UnwiredBuildInfoRepository"),

("apps/server/lib/composition/composition_root.dart",
 "    // Health slice.\n    final checkHealth = CheckHealth(PostgresHealthRepository(connection));",
 "    // Health slice.\n    final checkHealth = CheckHealth(PostgresHealthRepository(connection));\n\n    // Platform update-check slice: reads the newest published Android build\n    // from GitHub Releases. Public/unauthenticated, like health.\n    final getLatestBuild = GetLatestBuild(\n      GithubBuildInfoRepository(http.Client()),\n    );",
 "composition_root.dart 6/7: التوصيل الفعلي في bootstrap"),

("apps/server/lib/composition/composition_root.dart",
 "      checkHealth: checkHealth,\n      authenticateRequest: AuthenticateRequest(verifier),",
 "      checkHealth: checkHealth,\n      getLatestBuild: getLatestBuild,\n      authenticateRequest: AuthenticateRequest(verifier),",
 "composition_root.dart 7/7: تمرير القيمة في نداء CompositionRoot._"),

# --- mobile: providers.dart ---
("apps/mobile/lib/core/providers.dart",
 "/// The typed Auth (identity) client over the shared transport.\n@Riverpod(keepAlive: true)\nAuthApi authApi(Ref ref) => AuthApi(ref.watch(apiTransportProvider));",
 "/// The typed Auth (identity) client over the shared transport.\n@Riverpod(keepAlive: true)\nAuthApi authApi(Ref ref) => AuthApi(ref.watch(apiTransportProvider));\n\n/// The typed App (platform update-check) client over the shared transport.\n///\n/// Consumed by [UpdateGate] on launch to read `GET /app/latest-build`.\n/// Deliberately unauthenticated — like the route it wraps — so it works\n/// even before sign-in. Like the other domain clients it holds no state and\n/// performs no HTTP of its own.\n@Riverpod(keepAlive: true)\nAppApi appApi(Ref ref) => AppApi(ref.watch(apiTransportProvider));",
 "providers.dart: إضافة appApiProvider"),

# --- mobile: app.dart ---
("apps/mobile/lib/app.dart",
 "import 'core/theme/app_theme.dart';\nimport 'core/theme/theme_controller.dart';\nimport 'features/auth/session_gate.dart';\nimport 'l10n/app_localizations.dart';",
 "import 'core/theme/app_theme.dart';\nimport 'core/theme/theme_controller.dart';\nimport 'features/auth/session_gate.dart';\nimport 'features/update/update_gate.dart';\nimport 'l10n/app_localizations.dart';",
 "app.dart: استيراد UpdateGate"),

("apps/mobile/lib/app.dart",
 "      home: const SessionGate(),",
 "      home: const UpdateGate(child: SessionGate()),",
 "app.dart: لفّ SessionGate بـ UpdateGate"),

# --- mobile: pubspec.yaml ---
("apps/mobile/pubspec.yaml",
 "  http: ^1.6.0\n\n  # State management",
 "  http: ^1.6.0\n\n  # Verified on pub.dev 2026-08-21: url_launcher 6.3.2 (SDK compatible).\n  # The ONLY use: opening the update-check `.apk` download URL in the\n  # system browser (`features/update/update_gate.dart`). This is a URL\n  # launch, not a network request, so it does not violate the \"no HTTP in\n  # apps/mobile\" boundary (ADR-002 \\xc2\\xa72.8) \\xe2\\x80\\x94 no `http` call is made here.\n  url_launcher: ^6.3.2\n\n  # State management",
 "pubspec.yaml: إضافة url_launcher"),
]

ok, skipped, failed = 0, 0, 0
for path, old, new, label in EDITS:
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"[FAIL] {label}: الملف غير موجود: {path}")
        failed += 1
        continue

    if new in content:
        print(f"[SKIP] {label}: مُطبَّق مسبقاً")
        skipped += 1
        continue

    count = content.count(old)
    if count != 1:
        print(f"[FAIL] {label}: النص المرجعي غير موجود بدقة (found={count}) في {path}")
        failed += 1
        continue

    content = content.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK]   {label}")
    ok += 1

print(f"\n--- التعديلات: {ok} تم / {skipped} مُطبَّق مسبقاً / {failed} فشل ---")
if failed:
    sys.exit(1)
PYEOF

if [[ $? -ne 0 ]]; then
  echo ""
  echo "توقف السكربت: بعض التعديلات فشلت (انظر [FAIL] أعلاه)." >&2
  echo "غالباً يعني أن composition_root.dart أو الملفات المذكورة تغيّرت عن النسخة المتوقعة." >&2
  echo "لا تُكمل التحقق (analyze/test) قبل مراجعة هذه الملفات يدوياً." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3) توليد الكود + التحقق (يطابق خطوات CI في build-verification.yml)
# ---------------------------------------------------------------------------
echo ""
echo "== flutter pub get (الحزمة الكاملة) =="
flutter pub get

echo ""
echo "== build_runner (apps/mobile) =="
(cd apps/mobile && dart run build_runner build --delete-conflicting-outputs)

echo ""
echo "== dart analyze --fatal-warnings . =="
dart analyze --fatal-warnings .

echo ""
echo "== dart format (تطبيق التنسيق) =="
dart format .

echo ""
echo "== import_lint (حدود Clean Architecture) =="
dart run tooling/import_lint/bin/import_lint.dart

echo ""
echo "== melos run test (كل حزم Dart) =="
dart run melos run test

echo ""
echo "== flutter test --coverage (apps/mobile) =="
(cd apps/mobile && flutter test --coverage)

echo ""
echo "=================================================================="
echo "تم بنجاح. الخطوات التالية:"
echo "  git status"
echo "  git add -A"
echo "  git commit -m 'feat: in-app update check (GET /app/latest-build)'"
echo "  git push"
echo "بعد push إلى main: CI يبني APK جديد وينشره تلقائياً على tag 'latest'؛"
echo "التطبيقات المثبَّتة ستكتشف الإصدار الجديد عبر published_at في أول فتح تالٍ."
echo "=================================================================="
