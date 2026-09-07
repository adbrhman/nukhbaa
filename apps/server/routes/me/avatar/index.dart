import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/avatar_url.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /me/avatar` -- set or replace the caller's own profile picture.
/// `DELETE /me/avatar` -- remove it.
///
/// The body is the image bytes themselves, not JSON: base64 inside a JSON
/// envelope would inflate every upload by a third for no gain, and the
/// content type is already a header. Everything else on this server speaks
/// JSON because it carries domain intents; an image carries none.
///
/// Both verbs return the same `MeResponseDto` as `GET /me`, so a client
/// refreshes its whole identity -- including the new `avatar_url` -- from the
/// one response rather than making a second call to discover what changed.
///
/// Size and format are checked by `User.validateAvatar` inside `SetAvatar`,
/// and again by the database CHECK from migration 0033. The edge only reads
/// the bytes and names the content type; it makes no judgement of its own.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _set(context),
    HttpMethod.delete => _clear(context),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _set(RequestContext context) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  // A content type is required rather than sniffed: guessing a format from
  // magic bytes would mean storing something the client never claimed, and
  // the allowed set is small enough that asking is no burden.
  final mime = context.request.headers[HttpHeaders.contentTypeHeader]
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  if (mime == null || mime.isEmpty) {
    return errorResponse(
      const AppError.validation(
        'identity.avatar_mime_missing',
        'يجب تحديد نوع الصورة في ترويسة Content-Type',
      ),
    );
  }

  final List<int> bytes;
  try {
    bytes = await context.request.bytes();
  } on Object {
    return errorResponse(
      const AppError.validation(
        'identity.avatar_unreadable',
        'تعذّرت قراءة بيانات الصورة',
      ),
    );
  }

  final result = await root.setAvatar(
    principal: principal,
    bytes: bytes,
    mime: mime,
  );
  return _meResponse(result);
}

Future<Response> _clear(RequestContext context) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.clearAvatar(principal: principal);
  return _meResponse(result);
}

Response _meResponse(Result<User> result) => switch (result) {
  Ok<User>(:final value) => Response.json(
    body: MeResponseDto(
      user: AuthenticatedUserDto(
        userId: value.id.value,
        role: value.role.name,
        status: value.status.name,
        email: value.email,
        displayName: value.displayName,
        avatarUrl: avatarUrlFor(value),
      ),
    ).toJson(),
  ),
  Err<User>(:final error) => errorResponse(error),
};
