import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/avatar_url.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// GET /me — returns the authenticated caller's canonical platform identity
/// (API ADR, Section 2: this is a *query*, command/query separated).
///
/// The request is already authenticated by the `bearerAuth` middleware in
/// `routes/me/_middleware.dart`, which provides the verified
/// [AuthenticatedUser] into the context; an unauthenticated request is rejected
/// there and never reaches this handler. Here we resolve the platform's
/// authoritative [User] record via the [GetCurrentUser] use-case (ensuring the
/// row exists on first sight) and project it to the versioned [MeResponseDto].
///
/// The returned role/status are the platform-owned values from the directory,
/// not the token's claims — the token established *who* the caller is; the
/// platform decides *what* it records about them (Security ADR, Section 2).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  // A third account on one phone (script 245): refused first, so nothing is
  // written for it -- no account row, no enrolment, no sighting. The terms
  // of the contest allow two accounts on a phone.
  final sighting = root.recordDeviceSighting;
  if (sighting != null) {
    final admitted = await sighting.admit(
      principal: principal,
      installId: context.request.headers[appInstallHeader],
    );
    if (admitted is Err<void>) {
      return errorResponse(admitted.error);
    }
  }

  final result = await root.getCurrentUser(principal);

  // Membership is not a decision this product asks anyone to make: opening the
  // app is the join. Deliberately AFTER the identity read and deliberately
  // unchecked -- EnrolInOpenSeasons swallows its own failures, and `/me` must
  // answer "who am I" even when the enrolment write cannot happen. The next
  // call retries by construction.
  await root.enrolInOpenSeasons(
    principal: principal,
    now: DateTime.now().toUtc(),
  );

  // The phone this account is played from (script 200), for the admin's
  // shared-phones list. Unchecked, as the join above: `/me` answers
  // whether or not the sighting could be written.
  if (sighting != null && result is Ok<User>) {
    await sighting(
      principal: principal,
      installId: context.request.headers[appInstallHeader],
    );
  }

  return switch (result) {
    Ok<User>(:final value) => Response.json(
      body: MeResponseDto(
        user: AuthenticatedUserDto(
          userId: value.id.value,
          role: value.role.name,
          status: value.status.name,
          email: value.email,
          displayName: value.displayName,
          avatarUrl: avatarUrlFor(value),
        ),
      ).toJson(),
    ),
    // A transient directory failure maps to 503 via the shared envelope so the
    // client can retry; no other error kind is expected on this path.
    Err<User>(:final error) => errorResponse(error),
  };
}
