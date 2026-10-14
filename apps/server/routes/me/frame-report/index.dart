import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `POST /me/frame-report` -- one app session's frame counts (migration
/// 0070), for the smoothness the admin dashboard shows across devices.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here. Every field is required; the
/// use-case refuses a report that cannot be true. Optional: `device_model`
/// (migration 0071) and `frozen_at_start` / `frozen_at_resume` (0170);
/// an app from before them omits them.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final build = requireString(body, 'build');
  final platform = requireString(body, 'platform');
  final ints = <String, Result<int>>{
    for (final field in const [
      'refresh_rate_hz',
      'frames',
      'slow_frames',
      'frozen_frames',
      'worst_frame_ms',
    ])
      field: requireInt(body, field),
  };
  for (final r in [build, platform]) {
    if (r is Err<String>) {
      return errorResponse(r.error);
    }
  }
  for (final r in ints.values) {
    if (r is Err<int>) {
      return errorResponse(r.error);
    }
  }
  int value(String field) => (ints[field]! as Ok<int>).value;
  final Object? rawModel = body['device_model'];
  if (rawModel != null && rawModel is! String) {
    return errorResponse(
      const AppError.validation(
        'request.field_invalid',
        'Field "device_model" must be a string',
      ),
    );
  }

  final openings = <String, int?>{};
  for (final field in const ['frozen_at_start', 'frozen_at_resume']) {
    final Object? raw = body[field];
    if (raw != null && raw is! int) {
      return errorResponse(
        AppError.validation(
          'request.field_invalid',
          'Field "$field" must be an integer',
        ),
      );
    }
    openings[field] = raw as int?;
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final limited = limitPlayerAppend(PlayerAppend.frameReport, principal);
  if (limited != null) {
    return limited;
  }

  final result = await root.recordFrameReport(
    principal: principal,
    report: FrameReport(
      build: (build as Ok<String>).value,
      platform: (platform as Ok<String>).value,
      refreshRateHz: value('refresh_rate_hz'),
      frames: value('frames'),
      slowFrames: value('slow_frames'),
      frozenFrames: value('frozen_frames'),
      worstFrameMs: value('worst_frame_ms'),
      deviceModel: rawModel as String?,
      frozenAtStart: openings['frozen_at_start'],
      frozenAtResume: openings['frozen_at_resume'],
    ),
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const FrameReportAckDto(recorded: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
