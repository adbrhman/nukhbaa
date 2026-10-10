import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/h2h/players/{id}` -- player [id]'s head-to-head month exactly
/// as they see it on `GET /me/h2h-league` (migration 0100): their state,
/// division, group table, rounds, opponents and points. Their own line is
/// the one marked `is_me`. Nothing about anybody's prediction is read.
///
/// An id that is not a UUID is `400`. Admin only: the gate lives in the
/// use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final userId = UserId.tryParse(id);
  if (userId is Err<UserId>) {
    return errorResponse(userId.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAdminDesk.player(
    principal: principal,
    userId: (userId as Ok<UserId>).value,
  );

  return switch (result) {
    Ok<MyH2hMonth>(:final value) => Response.json(
      body: myH2hMonthToDto(value).toJson(),
    ),
    Err<MyH2hMonth>(:final error) => errorResponse(error),
  };
}
