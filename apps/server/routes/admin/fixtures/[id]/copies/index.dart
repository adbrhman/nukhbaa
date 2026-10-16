import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_merge_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/fixtures/{id}/copies` -- the fixture and the other copies of
/// its match, each with its predictions, doubles, result and provider link
/// (read `AdminListFixtureCopies`, migration 0176, script 95): what the
/// admin looks at before merging. Admin only, decided in the use-case. Any
/// other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminListFixtureCopies(
    principal: principal,
    fixtureId: id,
  );

  return switch (result) {
    Ok<List<FixtureCopy>>(:final value) => Response.json(
      body: fixtureCopiesToDto(value).toJson(),
    ),
    Err<List<FixtureCopy>>(:final error) => errorResponse(error),
  };
}
