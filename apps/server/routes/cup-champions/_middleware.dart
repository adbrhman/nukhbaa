import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the `/cup-champions` subtree with bearer authentication: the
/// champions of the cup and their pictures are shown to every signed-in
/// player, like the month's champions, and to nobody else.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
