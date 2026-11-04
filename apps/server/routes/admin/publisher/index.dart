import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `/admin/publisher` -- the sports publisher's panel (migration 0200).
///
/// * `GET` answers [PublisherOverviewDto]: the mode, each platform's
///   setting, the matches of the coming three days (picked ones marked),
///   the latest 60 posts, the club colours and the linked accounts.
/// * `PUT` sets one platform: a [PublisherSettingDto] body; answers it.
///   `400 publisher.setting_out_of_bounds` for a hold outside 1-30
///   minutes, a gap over an hour or a cap outside 0-50.
///
/// Admin only, decided in the use-case. `409 publisher.unavailable` while
/// `NUKHBA_PUBLISHER` is off.
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final admin = (adminRead as Ok<AdminPublisher>).value;

  if (method == HttpMethod.get) {
    final result = await admin.overview(principal: principal);
    return switch (result) {
      Ok<PublisherOverview>(:final value) => Response.json(
        body: publisherOverviewDto(value).toJson(),
      ),
      Err<PublisherOverview>(:final error) => errorResponse(error),
    };
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final setting = publisherSettingOf(
    PublisherSettingDto.fromJson(
      (bodyResult as Ok<Map<String, Object?>>).value,
    ),
  );
  if (setting is Err<PlatformIntensity>) {
    return errorResponse(setting.error);
  }
  final result = await admin.setIntensity(
    principal: principal,
    intensity: (setting as Ok<PlatformIntensity>).value,
  );
  return switch (result) {
    Ok<PlatformIntensity>(:final value) => Response.json(
      body: publisherSettingDto(value).toJson(),
    ),
    Err<PlatformIntensity>(:final error) => errorResponse(error),
  };
}
