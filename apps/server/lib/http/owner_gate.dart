import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// The body dart_frog 1.2.6 answers a path with no route
/// (`Router._defaultNotFound`).
const String routeNotFoundBody = 'Route not found';

/// What anyone but an owner seat gets under `/owner`: the very answer of a
/// path with no route, so the owners' page cannot be told from nothing.
Response ownerRouteNotFound() =>
    Response(statusCode: HttpStatus.notFound, body: routeNotFoundBody);

const Set<HttpMethod> _writes = <HttpMethod>{
  HttpMethod.post,
  HttpMethod.put,
  HttpMethod.patch,
  HttpMethod.delete,
};

/// Guards the whole `/owner` subtree (script 287, decision Q01, decided by
/// the owner on 2026-11-19): only an owner seat, primary or backup
/// ([OwnerNotices.isOwner], migration 0217), reaches a route there.
///
/// Anyone else -- an admin, a player, a request with no token or a bad one,
/// or a seat that cannot be read -- gets [ownerRouteNotFound], never `401`
/// or `409`: nothing tells that the page exists. The routes behind it read
/// the [AuthenticatedUser] this gate provides, as behind `bearerAuth`.
///
/// Every change an owner makes (a write answered below `400`) is kept in
/// the owners' own audit log ([OwnerAuditLog], migration 0219), never in
/// the admins'; a failure to keep it is printed and the answer goes out.
// NK287_03
Middleware ownerGate() {
  return (handler) {
    return (context) async {
      final root = await context.read<Future<CompositionRoot>>();
      final OwnerNotices? owners = root.ownerNotices;
      if (owners == null) {
        return ownerRouteNotFound();
      }

      final verified = await root.authenticateRequest(
        context.request.headers[HttpHeaders.authorizationHeader],
      );
      if (verified is! Ok<AuthenticatedUser>) {
        return ownerRouteNotFound();
      }
      final AuthenticatedUser principal = verified.value;
      final Result<bool> seat = await owners.isOwner(principal.userId);
      if (seat is! Ok<bool> || !seat.value) {
        return ownerRouteNotFound();
      }

      final Response response = await handler(
        context.provide<AuthenticatedUser>(() => principal),
      );

      final HttpMethod method = context.request.method;
      final OwnerAuditLog? audit = root.ownerAuditLog;
      if (audit != null &&
          _writes.contains(method) &&
          response.statusCode < HttpStatus.badRequest) {
        final Result<void> kept = await audit.record(
          actor: principal.userId,
          method: method.value,
          path: context.request.uri.path,
          status: response.statusCode,
        );
        if (kept case Err<void>(:final error)) {
          // ignore: avoid_print
          print('[owner-audit] not kept: ${error.code} ${error.message}');
        }
      }
      return response;
    };
  };
}
