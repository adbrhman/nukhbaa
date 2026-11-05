import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /admin/publisher/accounts/probe` -- asks Instagram, without
/// publishing anything, whether a post would go through: its permission
/// and that it can fetch the picture. Answers one [PublisherAccountDto]
/// for `instagram`; `ok` false carries the reason. Admin only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.probeInstagram(
    principal: principal,
  );
  return switch (result) {
    Ok<Result<String>>(:final value) => Response.json(
      body: PublisherAccountDto(
        platform: 'instagram',
        ok: value is Ok<String>,
        detail: switch (value) {
          Ok<String>(value: final line) => line,
          Err<String>(:final error) => error.message,
        },
      ).toJson(),
    ),
    Err<Result<String>>(:final error) => errorResponse(error),
  };
}
