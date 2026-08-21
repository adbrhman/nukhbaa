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
