import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards `/crests` with bearer authentication (script 265): any signed-in
/// player reads the club crests the app may show.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
