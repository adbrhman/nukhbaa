import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the `/champions` subtree with bearer authentication: the champions
/// and their pictures are shown to every signed-in player, like the avatars
/// on the boards, and to nobody else.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
