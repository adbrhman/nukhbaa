import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/crests/{slug}` `{"action": "hide" | "show" | "delete",
/// "reason": "...", "complainant": "...", "confirm": "<slug>"}` -- the
/// owner admin alone hides a club crest from every phone, shows it again,
/// or deletes it for good, its file erased (`confirm` must be the slug,
/// typed) (`OwnerCrests`, script 265, migration 0210). Answers
/// `{"status": "hidden" | "active" | "deleted"}`.
///
/// Any other admin is `409 admin.owner_only`; a blank reason is
/// `400 crest.reason_required`; a mistyped name `400 crest.confirm_mismatch`;
/// an unknown crest `409 crest.not_found`; a crest not in a state for it
/// `409 crest.state`; an unknown action `400 crest.action_invalid`. `405` on
/// any other method.
Future<Response> onRequest(RequestContext context, String slug) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final crests = root.ownerCrests;
  if (crests == null) {
    return errorResponse(
      const AppError.transient(
        'crests.unavailable',
        'The crests are unavailable',
      ),
    );
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Map<String, Object?> body =
      (bodyResult as Ok<Map<String, Object?>>).value;
  String? text(String field) =>
      body[field] is String ? body[field]! as String : null;
  final principal = context.read<AuthenticatedUser>();

  final (Result<void> result, String status) = switch (text('action')) {
    'hide' => (
      await crests.hide(
        principal: principal,
        slug: slug,
        reason: text('reason'),
        complainant: text('complainant'),
      ),
      'hidden',
    ),
    'show' => (
      await crests.show(
        principal: principal,
        slug: slug,
        reason: text('reason'),
      ),
      'active',
    ),
    'delete' => (
      await crests.delete(
        principal: principal,
        slug: slug,
        confirm: text('confirm'),
        reason: text('reason'),
        complainant: text('complainant'),
      ),
      'deleted',
    ),
    _ => (
      const Result<void>.err(
        AppError.validation(
          'crest.action_invalid',
          'action must be hide, show or delete',
        ),
      ),
      '',
    ),
  };
  return switch (result) {
    Ok<void>() => Response.json(body: {'status': status}),
    Err<void>(:final error) => errorResponse(error),
  };
}
