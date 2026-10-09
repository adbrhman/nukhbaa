import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `DELETE /admin/h2h/rounds/{id}` -- withdraws a round (migration 0100).
///
/// Only the last round of a month, and only before its first match kicks
/// off: anything else is `409` (`h2h.round_not_last`, `h2h.round_locked`);
/// an unknown round is `400` (`h2h.round_unknown`). Answers `204`.
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final roundId = H2hRoundId.tryParse(id);
  if (roundId is Err<H2hRoundId>) {
    return errorResponse(roundId.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.withdrawH2hRound(
    principal: principal,
    roundId: (roundId as Ok<H2hRoundId>).value,
  );

  return switch (result) {
    Ok<void>() => Response(statusCode: HttpStatus.noContent),
    Err<void>(:final error) => errorResponse(error),
  };
}
