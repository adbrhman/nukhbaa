import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/rate_limit.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:server/http/support_image_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/support/images` -- the caller sends support a picture
/// (migration 0188): the body is the image bytes, the type in
/// `Content-Type` (JPEG, PNG or WEBP, at most 512 KB, its signature
/// checked). It is a message of its own, with no text; 20 a day.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final limited = limitPlayerAppend(PlayerAppend.supportImage, principal);
  if (limited != null) return limited;
  final read = await readSupportImage(context.request);
  if (read is Err<(List<int>, String?)>) return errorResponse(read.error);
  final (List<int> bytes, String? mime) =
      (read as Ok<(List<int>, String?)>).value;
  final result = await root.sendSupportImage(
    principal: principal,
    bytes: bytes,
    mime: mime,
  );
  if (result is Ok<SupportMessageStored>) {
    notifySupportMessageLater(root, result.value);
  }
  return switch (result) {
    Ok<SupportMessageStored>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: supportMessageDto(value.message).toJson(),
    ),
    Err<SupportMessageStored>(:final error) => errorResponse(error),
  };
}
