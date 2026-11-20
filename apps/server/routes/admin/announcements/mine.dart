import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/announcement_request_wire.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK290_08
/// `GET /admin/announcements/mine` -- the signed-in admin's latest
/// announcements held for review, and where each stands: `pending`,
/// `published` or `rejected` (`SubmitAnnouncement.mine`, script 290). It
/// never names who reviewed them. `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final SubmitAnnouncement? submit = root.submitAnnouncement;
  if (submit == null) {
    return errorResponse(
      const AppError.transient(
        'notification.announcements_unavailable',
        'Announcements are unavailable',
      ),
    );
  }
  final Result<List<AnnouncementRequest>> mine = await submit.mine(
    principal: context.read<AuthenticatedUser>(),
  );
  return switch (mine) {
    Ok<List<AnnouncementRequest>>(:final value) => Response.json(
      body: announcementRequestsWire(value).toJson(),
    ),
    Err<List<AnnouncementRequest>>(:final error) => errorResponse(error),
  };
}
