import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/publisher_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/publisher/accounts` -- asks Facebook and Instagram whose
/// account the server's token opens. Answers `{"accounts": [...]}` of
/// [PublisherAccountDto]; a platform with no token is not listed. The
/// tokens stay on the server: only the account's name comes back. Admin
/// only.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final adminRead = adminPublisherOf(root);
  if (adminRead is Err<AdminPublisher>) {
    return errorResponse(adminRead.error);
  }
  final result = await (adminRead as Ok<AdminPublisher>).value.checkAccounts(
    principal: principal,
  );
  return switch (result) {
    Ok<Map<PublishPlatform, Result<String>>>(:final value) => Response.json(
      body: <String, Object?>{
        'accounts': <Object?>[
          for (final entry in value.entries)
            PublisherAccountDto(
              platform: entry.key.wire,
              ok: entry.value is Ok<String>,
              detail: switch (entry.value) {
                Ok<String>(value: final name) => name,
                Err<String>(:final error) => error.message,
              },
            ).toJson(),
        ],
      },
    ),
    Err<Map<PublishPlatform, Result<String>>>(:final error) => errorResponse(
      error,
    ),
  };
}
