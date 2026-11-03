import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the whole `/admin` subtree with bearer authentication (Security ADR
/// §2), mirroring `/participants` and `/notifications`.
///
/// Authentication (a verified principal) is enforced here at the subtree edge;
/// **authorization** (the caller is a `PlatformRole.admin`) is enforced INSIDE
/// each admin use-case (`SuspendUser`/`ReinstateUser`/`ListAuditLog`/
/// `ViewParticipantLedger` all call `Authorization.requireRole(principal,
/// PlatformRole.admin)` first — Admin Panel decision §2 #2, Security ADR §2.3).
/// So this middleware only establishes WHO the caller is; whether they are
/// allowed is the use-case's call: a well-formed request from a non-admin is
/// refused as `401 auth.insufficient_role`, never by a separate route-layer
/// gate. A route that checks its method, body or query before calling its
/// use-case answers a wrong one (`405`, `400`) before that refusal, to any
/// signed-in caller (audit 41; `app/min-build` is one): such an answer
/// tells a non-admin the route's input rules, never its data, and changes
/// nothing. There is deliberately NO separate admin auth path
/// (decision §2 #2 — admin is the existing `PlatformRole.admin` on the shipped
/// identity/JWT model), so this reuses `bearerAuth` unchanged.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
