import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bearer_auth.dart';

/// Guards the whole `/leaderboard` subtree with bearer authentication
/// (Security ADR §2), mirroring `/notifications`.
///
/// Unlike `/seasons/{id}/leaderboard`, this subtree carries NO membership gate
/// — the Hall of Fame is intentionally public to any authenticated user
/// (`GetHallOfFame` requires only `PlatformRole.user`). Authentication alone
/// (not authorization) is all this middleware adds; the use-case itself
/// performs the (deliberately minimal) authorization check.
Handler middleware(Handler handler) {
  return handler.use(bearerAuth());
}
