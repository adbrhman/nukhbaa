import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/fixtures/{id}/predictions` — the admin **fixture
/// raw-predictions** bulk read: every participant's predicted scorelines for
/// one fixture (docs/project-context.md, Axiom 4 Amendment — Step 3 of the
/// 7.10.x Round -> Season/Fixture migration; mirrors
/// `GET /admin/rounds/{id}/predictions`). Admin-only, enforced inside
/// `AdminListFixturePredictions`.
///
/// Unlike the Round-side sibling (gated on the round being `scored`), this
/// carries NO fixture-status gate — following `GetFixtureScores`'s Option-3
/// live/partial philosophy: an empty array means no one has predicted this
/// fixture (yet), not an error. The read is itself audited
/// (`fixture_predictions_viewed`), matching
/// `GET /admin/rounds/{id}/predictions`.
///
/// An optional `?reason=` query parameter is passed through to the audit
/// record; when supplied it must be non-blank (the domain `AuditEntry.create`
/// enforces this).
///
/// Returns a JSON array of [FixturePredictionDto] (`200`) — the same wire
/// shape as the participant-facing submit endpoint. `405` on any non-GET
/// method.
///
/// The `/admin` subtree is already behind `bearerAuth`
/// (`routes/admin/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this
/// handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final reason = context.request.uri.queryParameters['reason'];

  final result = await root.adminListFixturePredictions(
    principal: principal,
    fixtureId: id,
    reason: reason,
  );

  return switch (result) {
    Ok<List<FixturePredictionView>>(:final value) => await _withDisplayNames(
      root,
      principal,
      value,
    ),
    Err<List<FixturePredictionView>>(:final error) => errorResponse(error),
  };
}

/// Joins each participant's display name onto the raw-predictions payload —
/// the same optional enrichment `GET /admin/fixtures/{id}/scores` performs,
/// via the same admin-gated `AdminGetParticipantDisplayNames`. A failed or
/// unwired name lookup degrades to no names (the field is then omitted from
/// the wire shape), never to an error: the predictions read is the primary
/// value here and must not fail on a cosmetic join.
Future<Response> _withDisplayNames(
  CompositionRoot root,
  AuthenticatedUser principal,
  List<FixturePredictionView> views,
) async {
  final namesResult = await root.adminGetParticipantDisplayNames(
    principal: principal,
    participantIds: [
      for (final view in views) view.prediction.participantId.value,
    ],
  );
  final names = namesResult is Ok<Map<String, String>>
      ? namesResult.value
      : const <String, String>{};
  return Response.json(
    body: [
      for (final view in views)
        fixturePredictionViewToJson(
          view,
          displayName: names[view.prediction.participantId.value] ?? '',
        ),
    ],
  );
}
