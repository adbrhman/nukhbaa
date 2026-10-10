import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_admin_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/jobs` -- runs the head-to-head league's jobs now, as the
/// scheduler runs them every five minutes (migration 0100): approve and
/// lock the rounds due, judge an ended month, draw an opened month. Each job
/// is idempotent, so running them early never does anything twice. Answers
/// what was done; a full run is written to the admin log.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAdminDesk.controls.runJobs(principal: principal);

  return switch (result) {
    Ok<H2hJobsRun>(:final value) => Response.json(
      body: h2hJobsRunToDto(value).toJson(),
    ),
    Err<H2hJobsRun>(:final error) => errorResponse(error),
  };
}
