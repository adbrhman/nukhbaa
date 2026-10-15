import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/app/min-build` -- makes the newest published release the
/// oldest Android build the service supports, or clears that (migration
/// 0113, batch 147). Body: `{"to_latest": true | false}`; answers the
/// newest release's build number and the stored minimum.
///
/// An app older than the minimum asks its player to update before going on.
/// A missing or non-boolean `to_latest` is `400` (`app.to_latest_required`);
/// a newest release with no build number is `400`
/// (`app.build_number_unknown`). Admin only: the gate lives in the
/// use-case.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final bool? toLatest = AppUpdatePolicyDto.toLatestOf(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );
  if (toLatest == null) {
    return errorResponse(
      const AppError.validation(
        'app.to_latest_required',
        'Field "to_latest" must be true or false',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.setMinSupportedBuild(
    principal: principal,
    toLatest: toLatest,
  );

  return switch (result) {
    Ok<AppUpdatePolicy>(:final value) => Response.json(
      body: AppUpdatePolicyDto(
        latestBuild: value.latestBuild,
        minSupportedBuild: value.minSupportedBuild,
      ).toJson(),
    ),
    Err<AppUpdatePolicy>(:final error) => errorResponse(error),
  };
}
