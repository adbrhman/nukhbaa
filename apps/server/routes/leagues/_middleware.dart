import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the `/leagues` catalog read with bearer authentication, exactly as
/// `/teams` is guarded: reference data, but not public data.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
