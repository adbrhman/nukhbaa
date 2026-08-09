import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/rounds/{id}/predictions` — the round-report **raw-predictions**
/// bulk read: every participant's predicted scorelines for one **scored**
/// round (Admin Panel decision OPEN-A #3 lineage: read-only, scoped to a
/// single round by explicit id, itself audited). Admin-only, enforced inside
/// `AdminListRoundPredictions`.
///
/// Unlike `GET /rounds/{id}/predictions/all` (whose gate is "caller is a
/// participant of the round's season", and which only requires the round be
/// locked), this is an admin-only bulk read of a **scored** round — the same
/// gate `GET /rounds/{id}/scores` uses — so the report's score half and raw
/// half become available together. A not-yet-scored round is `409`
/// `admin.round_not_scored`. The read is itself audited
/// (`round_predictions_viewed`), matching `GET /admin/participants/{id}/ledger`.
///
/// An optional `?reason=` query parameter is passed through to the audit
/// record; when supplied it must be non-blank (the domain `AuditEntry.create`
/// enforces this).
///
/// Returns a JSON array of [PredictionDto] (`200`) — the same wire shape as
/// the participant-facing endpoint, so the mobile admin round-report screen
/// reuses one mapper; an empty array means the round is scored but no one
/// predicted. `405` on any non-GET method.
///
/// The `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final reason = context.request.uri.queryParameters['reason'];

  final result = await root.adminListRoundPredictions(
    principal: principal,
    roundId: id,
    reason: reason,
  );

  return switch (result) {
    Ok<List<PredictionView>>(:final value) => Response.json(
      body: [for (final view in value) predictionViewToJson(view)],
    ),
    Err<List<PredictionView>>(:final error) => errorResponse(error),
  };
}
