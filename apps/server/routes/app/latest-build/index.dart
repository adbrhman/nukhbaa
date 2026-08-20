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
