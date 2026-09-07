import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the `/users` subtree with bearer authentication.
///
/// Profile pictures are shown on leaderboards to signed-in participants, so
/// the gate is "be a member of this platform", not "be this user" -- the
/// picture is meant to be seen. Leaving it open instead would turn the
/// endpoint into a public probe for which user ids exist.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
