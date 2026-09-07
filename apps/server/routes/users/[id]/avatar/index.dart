import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /users/{id}/avatar` -- serves a user's stored profile picture.
///
/// The one route in this server that returns bytes rather than JSON, and the
/// only caller of `UserDirectory.readAvatar`, so image data never travels on
/// any other path.
///
/// A user with no picture is `404`, not an error envelope with a code: the
/// client renders the display-name initial in that case, and an image request
/// that finds no image is exactly what 404 means.
///
/// Cached for a year and marked immutable. That is safe precisely because the
/// URL carries `?v=<avatarUpdatedAt>`: a replaced picture is a different URL,
/// so nothing stale can survive, and an unchanged one is fetched once per
/// device forever. `private` because the bytes are a person's face -- a shared
/// proxy has no business holding them.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final idResult = UserId.tryParse(id);
  if (idResult is Err<UserId>) {
    return errorResponse(idResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.readAvatar(
    principal: principal,
    targetUserId: (idResult as Ok<UserId>).value,
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
