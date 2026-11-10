import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/app/min-play-build` -- stores the oldest Google Play build
/// the service supports, or clears it (migration 0206, script 253). Body:
/// `{"build_number": <versionCode> | null}`; answers the stored minimum.
///
/// A Play build older than it asks its player to update from the store;
/// the APK minimum (`PUT /admin/app/min-build`) is not touched. A missing
/// or non-integer `build_number` is `400` (`app.build_number_required`);
/// a number below 1 or above Play's ceiling is `400`
/// (`app.play_build_invalid`). Admin only: the gate lives in the use-case.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final PlayBuildNumberField field = PlayUpdatePolicyDto.buildNumberOf(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );
  if (!field.valid) {
    return errorResponse(
      const AppError.validation(
        'app.build_number_required',
        'Field "build_number" must be a whole number or null',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.setMinSupportedPlayBuild(
    principal: principal,
    buildNumber: field.value,
  );

  return switch (result) {
    Ok<int?>(:final value) => Response.json(
      body: PlayUpdatePolicyDto(minSupportedPlayBuild: value).toJson(),
    ),
    Err<int?>(:final error) => errorResponse(error),
  };
}
