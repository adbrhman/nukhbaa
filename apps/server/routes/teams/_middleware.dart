import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the whole `/teams` subtree with bearer authentication (Security ADR
/// §2). The catalog itself carries no per-user visibility/ownership concept —
/// any authenticated user may browse it (mirrors `/competitions`).
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
