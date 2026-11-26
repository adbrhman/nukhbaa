import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK343_02
/// `GET /owner/audit` -- what the owner seats did, on the owner page and
/// inside the admins' tools, the newest first (`ListOwnerAudit`, script 343,
/// plan 339 to 348).
///
/// Anyone but an owner seat gets the owner gate's `404` before this runs
/// (script 287); the use-case checks the seat again. `405` on any other
/// method. An optional `?limit=` that is not an integer is taken as absent.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final ListOwnerAudit? audit = root.listOwnerAudit;
  if (audit == null) {
    return errorResponse(
      const AppError.transient(
        'owner.audit_unavailable',
        'The owner audit log is unavailable',
      ),
    );
  }
  final String? rawLimit = context.request.uri.queryParameters['limit'];
  final Result<List<OwnerAuditLine>> listed = await audit(
    principal: context.read<AuthenticatedUser>(),
    limit: rawLimit == null ? null : int.tryParse(rawLimit),
  );
  return switch (listed) {
    Ok<List<OwnerAuditLine>>(:final value) => Response.json(
      body: OwnerAuditLogDto(
        entries: <OwnerAuditEntryDto>[
          for (final OwnerAuditLine line in value)
            OwnerAuditEntryDto(
              source: line.source,
              id: line.id,
              actorName: line.actorName,
              method: line.method,
              path: line.path,
              at: line.at,
              target: line.target,
              result: line.result,
            ),
        ],
      ).toJson(),
    ),
    Err<List<OwnerAuditLine>>(:final error) => errorResponse(error),
  };
}
