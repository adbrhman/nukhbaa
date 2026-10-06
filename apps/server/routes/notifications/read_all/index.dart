import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /notifications/read_all` -- mark every one of the caller's OWN
/// unread notifications read: the app calls it when the inbox is opened, so
/// the bell's count clears and comes back only with the next notification.
///
/// **Recipient-only (decision #4):** the recipient is the verified token's
/// user inside `MarkAllNotificationsRead`; this route makes no authorization
/// decision. No request body.
///
/// **Idempotent:** a repeat marks nothing; `marked` says how many went from
/// unread to read. `405` on any non-POST method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.markAllNotificationsRead(principal: principal);

  return switch (result) {
    Ok<int>(:final value) => Response.json(body: {'marked': value}),
    Err<int>(:final error) => errorResponse(error),
  };
}
