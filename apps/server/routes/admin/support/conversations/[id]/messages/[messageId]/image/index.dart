import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/support_image_body.dart';

/// `GET /admin/support/conversations/{id}/messages/{messageId}/image` --
/// a picture of conversation {id} (migration 0188); `404` when the message
/// is not in it or carries none. Admin only, in the use-case.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String messageId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  return supportImageResponse(
    await root.adminGetSupportImage(
      principal: principal,
      conversationId: id,
      messageId: int.tryParse(messageId),
    ),
  );
}
