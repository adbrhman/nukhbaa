import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/time-zone` -- record the calling device's offset from UTC.
///
/// Body: `{ "utc_offset_minutes": int }`. The owner comes from the verified
/// token, never the body (Security ADR §2).
///
/// Idempotent: the app calls this on every launch, and the write is an
/// unconditional column update, so a repeat is a re-confirmation rather than
/// a second effect.
///
/// **What it is not:** this offset moves no day boundary. The daily
/// challenge, the streak and `gamification.daily_active_users` stay on the
/// Riyadh day the fixture and result syncs already use. The offset exists so
/// a later notification can respect the reader's own clock (quiet hours).
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final offsetMinutes = requireInt(body, 'utc_offset_minutes');
  if (offsetMinutes is Err<int>) {
    return errorResponse(offsetMinutes.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.updateTimeZoneOffset(
    principal: principal,
    offsetMinutes: (offsetMinutes as Ok<int>).value,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const TimeZoneAckDto(recorded: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
