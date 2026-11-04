import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /admin/publisher/posts/{id}` -- an admin's hand on one post.
/// Body: `{"action": "retry" | "cancel" | "shared"}`:
///
/// * `retry` puts a failed, uncertain, skipped, cancelled or dry-run post
///   back in the queue, due at once (an uncertain one may already be on
///   the platform: the panel says so before);
/// * `cancel` keeps a queued or prepared post from ever going out;
/// * `shared` records that an admin shared a prepared X post by hand.
///
/// Answers `{"id": ..., "action": ...}`; `409 publisher.post_state` when
/// the post is not in a state the action applies to. Admin only.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Object? raw = (bodyResult as Ok<Map<String, Object?>>).value['action'];
  final action = switch (raw) {
    'retry' => PostAction.retry,
    'cancel' => PostAction.cancel,
    'shared' => PostAction.shared,
    _ => null,
  };
  if (action == null) {
    return errorResponse(
      const AppError.validation(
        'publisher.action_invalid',
        'Field "action" must be retry, cancel or shared',
      ),
    );
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.act(
    principal: principal,
    postId: id,
    action: action,
  );
  return switch (result) {
    Ok<void>() => Response.json(
      body: <String, Object?>{'id': id, 'action': raw},
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
