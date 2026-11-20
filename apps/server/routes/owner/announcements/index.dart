import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/announcement_request_wire.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK290_09
/// `GET /owner/announcements` -- the admins' announcements held for an
/// owner seat, the pending first, then the latest decided
/// (`OwnerAnnouncementReview`, script 290).
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287).
/// `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
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
  final Result<List<AnnouncementRequest>> listed = await review.list(
    principal: context.read<AuthenticatedUser>(),
  );
  return switch (listed) {
    Ok<List<AnnouncementRequest>>(:final value) => Response.json(
      body: announcementRequestsWire(value).toJson(),
    ),
    Err<List<AnnouncementRequest>>(:final error) => errorResponse(error),
  };
}
