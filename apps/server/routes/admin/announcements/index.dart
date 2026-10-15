import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/announcements` — publish one instruction to every active user
/// (API ADR §2: command intent `PublishAnnouncement`).
///
/// Admin-only, enforced inside the use-case
/// (`Authorization.requireRole(principal, PlatformRole.admin)` first —
/// Security ADR §2.3). The acting admin is bound from the verified token,
/// never a body, and the **audience is never client-supplied**: the server
/// resolves every active user itself, so a request can neither target nor
/// exclude anyone.
///
/// The only client-supplied values are the headline and the text. A blank or
/// over-long value is a `400` validation failure from the domain
/// (`notification.announcement_*`), never a silent empty broadcast.
///
/// The fan-out is idempotent per announcement id. An optional `request_id`
/// (a UUID the app makes once per message) becomes that id (audit M-14), so
/// "send" pressed again after a timeout reaches nobody twice and answers
/// how many inboxes the replay added (0 when the first one finished).
/// Without one, each POST mints a new id and re-posting sends again. Returns
/// [AnnouncementPublishedDto] (`200`) with the number of inboxes reached.
/// `405` on any non-POST method.
///
/// The `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  // Read defensively rather than through the DTO factory: a missing or
  // wrong-typed field becomes an empty string so the DOMAIN reports it as
  // `notification.announcement_title_empty`, keeping one validation voice
  // instead of a cast failure here.
  final title = body['title'];
  final text = body['body'];
  final requestId = body['request_id'];
  if (requestId != null && requestId is! String) {
    return errorResponse(
      const AppError.validation(
        'request.field_invalid',
        'Field "request_id" must be a string',
      ),
    );
  }

  final result = await root.publishAnnouncement(
    principal: principal,
    title: title is String ? title : '',
    body: text is String ? text : '',
    requestId: requestId as String?,
  );

  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: AnnouncementPublishedDto(recipients: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
