import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/fixture-visibility` -- hides fixtures from the players, or
/// shows them again (migration 0098; command `AdminSetFixturesHidden`).
///
/// Body: `{"fixture_ids": [uuid, ...], "hidden": true | false}` -- one
/// fixture or a whole selection, the same call. Answers the fixtures whose
/// state changed. Admin only, decided in the use-case. A missing or
/// malformed field is `400`; any other method is `405`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final List<String>? fixtureIds = FixtureVisibilityRequestDto.fixtureIdsOf(
    body,
  );
  if (fixtureIds == null) {
    return errorResponse(
      const AppError.validation(
        'competition.fixture_ids_invalid',
        'Field "fixture_ids" must be a list of fixture ids',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminSetFixturesHidden(
    principal: principal,
    fixtureIds: fixtureIds,
    hidden: FixtureVisibilityRequestDto.hiddenOf(body),
  );

  return switch (result) {
    Ok<List<FixtureRef>>(:final value) => Response.json(
      body: FixtureVisibilityResultDto(
        changed: [for (final fixture in value) fixture.value],
        hidden: FixtureVisibilityRequestDto.hiddenOf(body) ?? false,
      ).toJson(),
    ),
    Err<List<FixtureRef>>(:final error) => errorResponse(error),
  };
}
