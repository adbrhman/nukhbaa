import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_ledger_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /fixtures/{id}/ledger` — post a **scored** fixture to the append-only
/// Ledger (API ADR §2: command intent `PostFixtureToLedger`;
/// docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `POST /rounds/{id}/ledger`). Admin-only, enforced inside the use-case
/// (Axioms 2/5).
///
/// No request body: the amounts are copied server-side from the fixture's
/// already-persisted `ParticipantFixtureScore`s. **Idempotent** (Axiom 4):
/// re-posting an already-posted fixture appends nothing new — the response's
/// `appended_entries` is empty.
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.postFixtureToLedger(
    principal: principal,
    fixtureId: id,
  );

  return switch (result) {
    Ok<List<FixturePointEntry>>(:final value) => Response.json(
      body: postFixtureToLedgerResponseJson(id, value),
    ),
    Err<List<FixturePointEntry>>(:final error) => errorResponse(error),
  };
}
