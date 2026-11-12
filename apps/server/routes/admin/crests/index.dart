import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `/admin/crests` -- the club crests, for the owner admin alone
/// (`OwnerCrests`, script 265, migration 0210).
///
/// * `GET` -- every crest (its status, its URL until deleted, why), the
///   switch and the latest 50 changes.
/// * `PUT` `{"clubs_enabled": bool, "reason": "..."}` -- turns every club
///   crest on or off. Answers `{"clubs_enabled": bool}`.
///
/// Any other admin is `409 admin.owner_only`; a blank reason is
/// `400 crest.reason_required`. `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  final HttpMethod method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.put) {
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
  final principal = context.read<AuthenticatedUser>();

  if (method == HttpMethod.put) {
    final bodyResult = await readJsonObject(context.request);
    if (bodyResult is Err<Map<String, Object?>>) {
      return errorResponse(bodyResult.error);
    }
    final Map<String, Object?> body =
        (bodyResult as Ok<Map<String, Object?>>).value;
    final Object? enabled = body['clubs_enabled'];
    if (enabled is! bool) {
      return errorResponse(
        const AppError.validation(
          'crest.switch_invalid',
          'clubs_enabled must be true or false',
        ),
      );
    }
    final Object? reason = body['reason'];
    final Result<void> set = await crests.setClubsEnabled(
      principal: principal,
      enabled: enabled,
      reason: reason is String ? reason : null,
    );
    return switch (set) {
      Ok<void>() => Response.json(body: {'clubs_enabled': enabled}),
      Err<void>(:final error) => errorResponse(error),
    };
  }

  final Result<CrestState> state = await crests.state(principal: principal);
  return switch (state) {
    Ok<CrestState>(:final value) => Response.json(
      body: AdminCrestsDto(
        clubsEnabled: value.list.clubsEnabled,
        crests: <AdminCrestDto>[
          for (final ClubCrest crest in value.list.crests)
            AdminCrestDto(
              slug: crest.slug,
              status: crest.status.wireValue,
              url: value.urlOf(crest),
              reason: crest.reason,
              complainant: crest.complainant,
              changedAt: crest.changedAt?.toUtc().toIso8601String(),
            ),
        ],
        events: <CrestEventDto>[
          for (final CrestEvent event in value.events)
            CrestEventDto(
              action: event.action,
              reason: event.reason,
              at: event.at.toUtc().toIso8601String(),
              slug: event.slug,
              complainant: event.complainant,
            ),
        ],
      ).toJson(),
    ),
    Err<CrestState>(:final error) => errorResponse(error),
  };
}
