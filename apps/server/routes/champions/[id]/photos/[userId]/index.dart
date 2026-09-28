import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /champions/{seasonId}/photos/{userId}` -- the celebration picture of
/// a crowned champion (migration 0077), as bytes.
///
/// No picture is `404`: the app then shows the champion's avatar or
/// initials. Cached for a year and immutable, like the avatars: the URL
/// carries `?v=<photo time>`, so a replaced picture is a different URL.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String userId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.readChampionPhoto(
    principal: principal,
    seasonId: id,
    userId: userId,
  );

  return switch (result) {
    Err<StoredAvatar?>(:final error) => errorResponse(error),
    Ok<StoredAvatar?>(:final value) =>
      value == null
          ? Response(statusCode: HttpStatus.notFound)
          : Response.bytes(
              body: value.bytes,
              headers: <String, String>{
                HttpHeaders.contentTypeHeader: value.mime,
                HttpHeaders.cacheControlHeader:
                    'private, max-age=31536000, immutable',
              },
            ),
  };
}
