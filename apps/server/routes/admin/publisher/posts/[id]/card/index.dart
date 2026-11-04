import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/publisher/posts/{id}/card` -- the post's picture (JPEG), to
/// preview it in the panel or to share it on X by hand. Admin only.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.card(
    principal: principal,
    postId: id,
  );
  return switch (result) {
    Ok<List<int>>(:final value) => Response.bytes(
      body: value,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'image/jpeg',
        HttpHeaders.cacheControlHeader: 'private, max-age=3600',
      },
    ),
    Err<List<int>>(:final error) => errorResponse(error),
  };
}
