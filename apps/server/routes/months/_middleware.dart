import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the `/months` read with bearer authentication, exactly as
/// `/competitions` and `/leagues` are guarded.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
