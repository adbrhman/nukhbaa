import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/error-releases` -- the error log by release and by file
/// (migration 0087): how many errors each recent build hit, and the files
/// most occurrences come from. Admins only; behind `bearerAuth` like all
/// of `/admin`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final summary = root.adminErrorReleases;
  if (summary == null) {
    return errorResponse(
      const AppError.transient(
        'errors.unavailable',
        'The error log is unavailable',
      ),
    );
  }
  final result = await summary(principal: principal);
  return switch (result) {
    Ok<AdminErrorReleasesView>(:final value) => Response.json(
      body: AdminErrorReleasesDto(
        releases: [
          for (final r in value.releases)
            AdminErrorReleaseDto(
              build: r.build,
              errors: r.errors,
              critical: r.critical,
              occurrences: r.occurrences,
              firstSeenAt: r.firstSeenAt,
              lastSeenAt: r.lastSeenAt,
            ),
        ],
        files: [
          for (final f in value.files)
            AdminErrorFileDto(
              file: f.file,
              errors: f.errors,
              occurrences: f.occurrences,
            ),
        ],
      ).toJson(),
    ),
    Err<AdminErrorReleasesView>(:final error) => errorResponse(error),
  };
}
