import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:server/http/support_image_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/support/conversations/{id}/images` -- an admin answers
/// with a picture, as "دعم نُخبة" (migration 0188): the image bytes, the
/// type in `Content-Type`. Admin only, in the use-case.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final read = await readSupportImage(context.request);
  if (read is Err<(List<int>, String?)>) return errorResponse(read.error);
  final (List<int> bytes, String? mime) =
      (read as Ok<(List<int>, String?)>).value;
  final result = await root.adminReplySupportImage(
    principal: principal,
    conversationId: id,
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
