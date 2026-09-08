import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/leaderboard_dto_mapper.dart';
import 'package:shared/shared.dart';

/// GET /me/seasons -- the caller's season-by-season record: every season they
/// have played, newest first, each with the place they took, the points they
/// scored, and the raw counts behind their accuracy.
///
/// **Visibility:** always the caller's own record. `ListMySeasonRecords`
/// scopes the read to `AuthenticatedUser.userId` and takes no user parameter
/// at all, so this route has no authorization decision of its own to make and
/// no way to address another person's history.
///
/// The `/me` subtree is already behind `bearerAuth`
/// (`routes/me/_middleware.dart`), so an unauthenticated request never
/// reaches this handler. An empty array means the caller has never scored in
/// any season -- a legitimate result for a new account, never an error.
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.listMySeasonRecords(principal: principal);

  return switch (result) {
    Ok<List<ParticipantSeasonRecord>>(:final value) => Response.json(
      body: [for (final record in value) mySeasonRecordToDto(record).toJson()],
    ),
    Err<List<ParticipantSeasonRecord>>(:final error) => errorResponse(error),
  };
}
