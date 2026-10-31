import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_absence_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/h2h/absence` -- relegation for absence this month (NK183,
/// migration 0189): the month's rounds and which count, the elite players
/// absent from the latest counted rounds, the next substitutes in the order
/// the rules take them, when the system swaps before the next round, and
/// every swap with its facts.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAbsenceDesk.view(principal: principal);

  return switch (result) {
    Ok<H2hAbsenceView>(:final value) => Response.json(
      body: h2hAbsenceViewToDto(value).toJson(),
    ),
    Err<H2hAbsenceView>(:final error) => errorResponse(error),
  };
}
