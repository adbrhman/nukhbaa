import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the whole `/duels` subtree with bearer authentication (Security
/// ADR, Section 2). Who may accept, cancel or decline a challenge is decided
/// inside each use-case and again by the 0090 database functions; this
/// middleware only proves the caller is signed in. Writes are counted by the
/// player write limiter `bearerAuth` already applies.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
