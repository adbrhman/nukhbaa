import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/duplicate-names` -- every display name more than one account
/// carries (`AdminListDuplicateNames`), as a [DuplicateNamesDto] (`200`). An
/// empty `groups` list means every chosen name is unique. Admin-only; `405`
/// on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminListDuplicateNames(principal: principal);

  return switch (result) {
    Ok<List<DuplicateNameGroup>>(:final value) => Response.json(
      body: DuplicateNamesDto(
        groups: [
          for (final group in value)
            [for (final user in group.users) userSummaryToDto(user)],
        ],
      ).toJson(),
    ),
    Err<List<DuplicateNameGroup>>(:final error) => errorResponse(error),
  };
}
