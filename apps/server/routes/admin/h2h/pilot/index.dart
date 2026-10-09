import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/pilot` -- draws the hidden pilot month (migration
/// 0100): every user assigned `h2h_pilot` = `pilot`, best points of the
/// month first, in groups of at most twenty. The pilot decides nothing:
/// its month closes without a single event.
///
/// Only before the league opens (`h2h.pilot_after_launch`) and once a
/// month (`h2h.pilot_already_drawn`): each is `409`. Fewer than two pilot
/// players is `400` (`h2h.pilot_too_small`). Answers the seats handed out.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.startH2hPilot(principal: principal);

  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: H2hPilotStartedDto(seated: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
