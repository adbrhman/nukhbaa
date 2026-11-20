import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

// NK290_10
/// `POST /owner/announcements/{id}` `{"action": "publish" | "reject"}` --
/// an owner seat publishes an admin's held announcement to every active
/// player, as he wrote it, or rejects it (`OwnerAnnouncementReview`,
/// script 290). Answers `{"status": "published", "recipients": n}` or
/// `{"status": "rejected"}`. Kept in the owners' audit log by the gate.
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287). An
/// unknown announcement is `409 announcement.request_not_found`; one
/// already decided `409 announcement.already_decided`; another action
/// `400 announcement.action_invalid`. `405` on any other method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final OwnerAnnouncementReview? review = root.ownerAnnouncementReview;
  if (review == null) {
    return errorResponse(
      const AppError.transient(
        'notification.announcements_unavailable',
        'Announcements are unavailable',
      ),
    );
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Object? action =
      (bodyResult as Ok<Map<String, Object?>>).value['action'];
  final principal = context.read<AuthenticatedUser>();
  switch (action) {
    case 'publish':
      final Result<int> sent = await review.publish(
        principal: principal,
        requestId: id,
      );
      return switch (sent) {
        Ok<int>(:final value) => Response.json(
          body: {'status': 'published', 'recipients': value},
        ),
        Err<int>(:final error) => errorResponse(error),
      };
    case 'reject':
      final Result<void> done = await review.reject(
        principal: principal,
        requestId: id,
      );
      return switch (done) {
        Ok<void>() => Response.json(body: {'status': 'rejected'}),
        Err<void>(:final error) => errorResponse(error),
      };
    default:
      return errorResponse(
        const AppError.validation(
          'announcement.action_invalid',
          'action must be publish or reject',
        ),
      );
  }
}
