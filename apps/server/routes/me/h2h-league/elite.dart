import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_admin_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /me/h2h-league/elite` -- the tables of the four elite groups of the
/// current head-to-head month (2026-11-08): each group's standings over the
/// settled rounds, best first, with the caller's own line marked (`is_me`).
/// Every player may read them. Before the elite draw (or while the month is
/// a hidden pilot, or not drawn) `groups` is empty.
///
/// Names, records and points only: no match, no prediction and no empty
/// seat crosses this wire. The shape is the admin's `H2hAdminGroupsDto`.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.getH2hEliteTables(principal: principal);

  return switch (result) {
    Ok<H2hAdminMonth>(:final value) => Response.json(
      body: h2hAdminGroupsToDto(value, viewer: principal.userId).toJson(),
    ),
    Err<H2hAdminMonth>(:final error) => errorResponse(error),
  };
}
