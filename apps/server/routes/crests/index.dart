import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /crests` -- the URL of every club crest the app may show, by slug
/// (`GetCrestManifest`, script 265, migration 0210). Read on every start of
/// the app: a crest absent from it is not shown, and the copy the app kept
/// is dropped. Its `version` is also the `ETag`: an `If-None-Match` that
/// carries it is `304` with no body. Any signed-in user; `405` on any
/// non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final read = root.getCrestManifest;
  if (read == null) {
    return errorResponse(
      const AppError.transient(
        'crests.unavailable',
        'The crests are unavailable',
      ),
    );
  }
  final result = await read(principal: context.read<AuthenticatedUser>());
  return switch (result) {
    Ok<CrestManifest>(:final value) => _answer(context, value),
    Err<CrestManifest>(:final error) => errorResponse(error),
  };
}

Response _answer(RequestContext context, CrestManifest manifest) {
  final String tag = '"${manifest.version}"';
  final Map<String, Object> headers = <String, Object>{
    HttpHeaders.etagHeader: tag,
    HttpHeaders.cacheControlHeader: 'no-cache',
  };
  if (context.request.headers[HttpHeaders.ifNoneMatchHeader] == tag) {
    return Response(statusCode: HttpStatus.notModified, headers: headers);
  }
  return Response.json(
    headers: headers,
    body: CrestManifestDto(
      version: manifest.version,
      clubsEnabled: manifest.clubsEnabled,
      crests: manifest.crests,
    ).toJson(),
  );
}
