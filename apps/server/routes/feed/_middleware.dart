import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the whole `/feed` read subtree with bearer authentication (Security
/// ADR §2), mirroring every other client-facing browse read.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
